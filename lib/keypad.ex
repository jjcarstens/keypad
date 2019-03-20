defmodule Keypad do
  @moduledoc """
  Documentation for Keypad.
  """
  @callback handle_keypress(key :: String.t) :: any

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      use GenServer, Keyword.drop(opts, [:row_pins, :col_pins, :matrix, :size])
      @behaviour Keypad

      alias __MODULE__

      defmodule State do
        defstruct row_pins: [17, 27, 5, 6], col_pins: [22, 23, 24, 25], matrix: nil, size: nil, last_message_at: 0
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
        {row_pin, row_index} = Enum.with_index(state.row_pins)
                               |> Enum.find(fn {row, _i} -> Circuits.GPIO.pin(row) == pin_num end)
        state.col_pins
        |> Stream.with_index()
        |> Enum.reduce_while([], fn {col, col_index}, acc ->
          Circuits.GPIO.write(col, 1)
          row_val = Circuits.GPIO.read(row_pin)
          Circuits.GPIO.write(col, 0)

          case row_val do
            1 ->
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
