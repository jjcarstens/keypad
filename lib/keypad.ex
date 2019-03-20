defmodule Keypad do
  @moduledoc """
  `keypad` is implemented as a `__using__` macro so that you can put it in any module you want
  to handle the keypress events. Because it is small GenServer, it [accepts the same options for supervision](https://hexdocs.pm/elixir/GenServer.html#module-how-to-supervise)
  to configure the child spec and passes them along to `GenServer`:

  ```elixir
  defmodule MyModule do
    use Keypad, restart: :transient, shutdown: 10_000
  end
  ```

  It also has its own set of options to pass to configure the keypad connections. At a minimum, you must
  pass either `:size` or a custom matrix with `:matrix`:

  * `:size` - If supplied without `:matrix` it will select the default matrix for the specified size. The delaration is `row x col`, so `:three_by_four` would be 3 rows, 1 column.
    * `:four_by_four` or `"4x4"` - Standard 12-digit keypad with `A`, `B`, `C`, and `D` keys
    * `:three_by_four` or `"3x4"` - Standard 12-digit keypad
    * `:one_by_four` or `"1x4"`
  * `:matrix` - A custom matrix to use for mapping keypresses to. Will take precedence over `:size` if supplied
    * Typically, these are `binary` values. However, these values are pulled from List and in theory can be
    anything you want. i.e. atom, integer, or even annonymous function
  * `:row_pins` - List of integers which map to corresponding GPIO to set as `INPUT` pins for keypard rows
    * On raspberry pi, these will also set the internal resistor to `PULL_UP` and inactive HIGH. For all other hardware, you will probably need to make sure to place some 10K resistors between your pin and ground. see [Setup](SETUP.md) doc for some examples
    * defaults to `[17, 27, 23, 24]`
  * `:col_pins` - List of integers which map to corresponding GPIO to as `OUTPUT` pins for keypad columns
    * defaults to `[5, 6, 13, 26]`
  """
  @callback handle_keypress(key :: any) :: any

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use GenServer, Keyword.drop(opts, [:row_pins, :col_pins, :matrix, :size])
      @behaviour Keypad

      alias __MODULE__

      defmodule State do
        defstruct row_pins: [17, 27, 23, 24], col_pins: [5, 6, 13, 26], matrix: nil, size: nil, last_message_at: 0
      end

      defguard valid_press(current, prev) when ((current - prev)/1.0e6) > 100

      def start_link do
        initial_state = struct(State, unquote(opts))
        GenServer.start_link(__MODULE__, initial_state, name: __MODULE__)
      end

      @impl true
      def init(state) do
        send self(), :init
        {:ok, state}
      end

      @impl true
      def handle_info(:init, state) do
        state = state
                |> initialize_matrix_and_size()
                |> initialize_rows_and_cols()

        {:noreply, state}
      end

      @impl true
      def handle_info({:circuits_gpio, pin_num, time, 0}, %{last_message_at: prev} = state) when valid_press(time, prev) do
        {row_pin, row_index} = Stream.with_index(state.row_pins)
                               |> Enum.find(fn {row, _i} -> Circuits.GPIO.pin(row) == pin_num end)
        state.col_pins
        |> Stream.with_index()
        |> Enum.reduce_while([], fn {col, col_index}, acc ->
          # Write the column pin HIGH then read the row pin again.
          # If the row is HIGH, then we've pin-pointed which column it is in
          Circuits.GPIO.write(col, 1)
          row_val = Circuits.GPIO.read(row_pin)
          Circuits.GPIO.write(col, 0)

          case row_val do
            1 ->
              # We can use the row and column indexes as x,y of the matrix
              # to get which specific key character the press belongs to.
              val = Enum.at(state.matrix, row_index) |> Enum.at(col_index)
              apply(__MODULE__, :handle_keypress, [val])
              {:halt, []}
            0 ->
              {:cont, []}
          end
        end)

        {:noreply, %{state | last_message_at: time}}
      end

      # ignore messages that are too quick or on button release
      @impl true
      def handle_info({:circuits_gpio, _, time, _}, state), do: {:noreply, state}

      defp initialize_rows_and_cols(%{size: <<x::binary-size(1), "x", y::binary-size(1)>>, row_pins: rows, col_pins: cols} = state) do
        # x == col
        # y == row
        if String.to_integer(x) != length(cols), do: raise ArgumentError, "expected #{x} column pins but only #{length(cols)} were given"
        if String.to_integer(y) != length(rows), do: raise ArgumentError, "expected #{x} row pins but only #{length(rows)} were given"

        row_pins = for pin_num <- rows do
          # Just use internal resistor if on a Raspberry Pi
          {:ok, pin} = Circuits.GPIO.open(pin_num, :input, pull_mode: :pullup)
          :ok = Circuits.GPIO.set_interrupts(pin, :falling)
          pin
        end

        col_pins = for pin_num <- cols do
          {:ok, pin} = Circuits.GPIO.open(pin_num, :output, initial_value: 0)
          pin
        end

        %{state | col_pins: col_pins, row_pins: row_pins}
      end

      defp initialize_matrix_and_size(%{matrix: matrix} = state) when is_list(matrix) do
        matrix
        |> Enum.map(&length/1)
        |> Enum.uniq
        |> case do
          [x_size] ->
            %{state | size: "#{x_size}x#{length(matrix)}"}
          _ ->
            raise ArgumentError, "matrix columns must be equal\n#{inspect(matrix)}"
        end
      end

      defp initialize_matrix_and_size(%{size: size, matrix: nil} = state) when not is_nil(size) do
        %{state | matrix: matrix_for_size(size)}
        |> initialize_matrix_and_size()
      end

      defp initialize_matrix_and_size(_) do
        raise ArgumentError, "must provide a keypad size or matrix"
      end

      defp matrix_for_size(:four_by_four), do: matrix_for_size("4x4")

      defp matrix_for_size(:three_by_four), do: matrix_for_size("3x4")

      defp matrix_for_size(:one_by_four), do: matrix_for_size("1x4")

      defp matrix_for_size("4x4") do
        [
          ["1", "2", "3", "A"],
          ["4", "5", "6", "B"],
          ["7", "8", "9", "C"],
          ["*", "0", "#", "D"]
        ]
      end

      defp matrix_for_size("3x4") do
        [
          ["1", "2", "3"],
          ["4", "5", "6"],
          ["7", "8", "9"],
          ["*", "0", "#"]
        ]
      end

      defp matrix_for_size("1x4") do
        [
          ["1", "2", "3", "4"]
        ]
      end

      defp matrix_for_size(size), do: raise ArgumentError, "unsupported matrix size: #{inspect(size)}"
    end
  end
end
