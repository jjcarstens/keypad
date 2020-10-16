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

  * `:size` - If supplied without `:matrix` it will select the default matrix for the specified size. The delaration is `row x col`, so `:one_by_four` would be 1 row, 4 columns.
    * `:four_by_four` or `"4x4"` - Standard 12-digit keypad with `A`, `B`, `C`, and `D` keys
    * `:four_by_three` or `"4x3"` - Standard 12-digit keypad
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

  @doc """
  Required callback to handle keypress events based on defined matrix values.

  It's first argument will be the result of the keypress according to the defined matrix (most typically a
  binary string, though you can use anything you'd like). The second argument is the state of the keypad
  GenServer. You are required to return the state in this function.

  There is an optional field in the state called `:input` which is initialized as an empty string `""`. You can
  use this to keep input events from keypresses and build them as needed, such as putting multiple keypresses
  together to determine a password. **Note**: You will be responsible for resetting this input as needed.

  This is not required and you can optionally use other measures to keep rolling state, such as `Agent`.

  ```elixir
  defmodule MyKeypad do
    use Keypad

    require Logger

    @impl true
    def handle_keypress(key, %{input: ""} = state) do
      Logger.info("First Keypress: \#{key}")
      Process.send_after(self(), :reset, 5000) # Reset input after 5 seconds
      %{state | input: key}
    end

    @impl true
    def handle_keypress(key, %{input: input} = state) do
      Logger.info("Keypress: \#{key}")
      %{state | input: input <> key}
    end

    @impl true
    def handle_info(:reset, state) do
      {:noreply, %{state | input: ""}}
    end
  end
  ```
  """
  @callback handle_keypress(key :: any, map) :: map

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use GenServer, Keyword.drop(opts, [:row_pins, :col_pins, :matrix, :size])
      @behaviour Keypad

      alias __MODULE__

      defmodule State do
        defstruct row_pins: [17, 27, 23, 24], col_pins: [5, 6, 13, 26], input: "", matrix: nil, size: nil, last_message_at: 0
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
        val = state.col_pins
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

              {:halt, val}
            0 ->
              {:cont, []}
          end
        end)

        state = apply(__MODULE__, :handle_keypress, [val, state])

        {:noreply, %{state | last_message_at: time}}
      end

      # ignore messages that are too quick or on button release
      @impl true
      def handle_info({:circuits_gpio, _, time, _}, state), do: {:noreply, state}

      defp initialize_rows_and_cols(%{size: <<x::binary-size(1), "x", y::binary-size(1)>>, row_pins: rows, col_pins: cols} = state) do
        # x == row
        # y == col
        if String.to_integer(x) != length(rows), do: raise ArgumentError, "expected #{x} row pins but only #{length(rows)} were given"
        if String.to_integer(y) != length(cols), do: raise ArgumentError, "expected #{y} column pins but only #{length(cols)} were given"

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

        %{state | row_pins: row_pins, col_pins: col_pins}
      end

      defp initialize_matrix_and_size(%{matrix: matrix} = state) when is_list(matrix) do
        matrix
        |> Enum.map(&length/1)
        |> Enum.uniq
        |> case do
          [y_size] ->
            %{state | size: "#{length(matrix)}x#{y_size}"}
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

      defp matrix_for_size(:four_by_three), do: matrix_for_size("4x3")

      defp matrix_for_size(:one_by_four), do: matrix_for_size("1x4")

      defp matrix_for_size("4x4") do
        [
          ["1", "2", "3", "A"],
          ["4", "5", "6", "B"],
          ["7", "8", "9", "C"],
          ["*", "0", "#", "D"]
        ]
      end

      defp matrix_for_size("4x3") do
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
