# Configuration

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

## Examples

Using a default matrix with custom row and column pins:
```elixir
defmodule MyModule do
  use Keypad, row_pins: [5,6,7], col_pins: [22,23,24,25], size: "3x4"

  @impl true
  def handle_keypress(key, state) do
    IO.inspect(key, label: "KEYPRESS: ")
    state
  end
end
```

Configuring a custom matrix and specific row and column pins:
```elixir
defmodule MyModule do
  use Keypad, row_pins: [5,6,7], col_pins: [22,23,24,25], matrix: [
    ["c", "o", "o", "l"],
    [:b, :e, :a, :n],
    [1, 2, 3, 4]
  ]

  @impl true
  def handle_keypress(key, state) do
    IO.inspect(key, label: "KEYPRESS: ")
    state
  end
end
```

Custom matrix using default pins:
```elixir
defmodule MyModule do
  use Keypad, matrix: [
    ["c", "o", "o", "l"],
    [:b, :e, :a, :n],
    [1, 2, 3, 4].
    ['*', '%', '#', "+"]
  ]

  @impl true
  def handle_keypress(key, state) do
    IO.inspect(key, label: "KEYPRESS: ")
    state
  end
end
```