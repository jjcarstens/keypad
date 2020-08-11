# Keypad

A small library to interact with keypads connected to GPIO pins.

Its really just a defined behavior macro to make setting up a keypad very easy to get up a running.
In theory, this can be used on any platform with GPIO pins, but is mainly developed with
the raspberry pi in mind.

It can be used with membrane or mechanical keypads, such as these:
* [Adafruit 3x4 Matrix Membrane Keypad](https://www.adafruit.com/product/419)
* [Adafruit 1x4 Matrix Membrane Keypad](https://www.adafruit.com/product/1332)
* [Adafruit 4x4 Matrix Keypad](https://www.adafruit.com/product/3844)

If you want to know more about how it works, I found [this article](http://www.circuitbasics.com/how-to-set-up-a-keypad-on-an-arduino/)
to be very helpful. In short, keypads are split into rows and columns and work by changing the
pin state HIGH/LOW on keypress. You then traverse your known pins and match it to a predefined matrix of characters
to determine which button is actually being pressed.

:warning: `keypad` sets the internal pull-up resistors on raspberry pi so you can plug every pin of the keypad
directly into the board. However, that is currently hardware dependent and not supported for other boards. For those,
see the [setup](SETUP.md) for determining your pinout and setup. 

## Installation

Add `keypad` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:keypad, "~> 0.3"}
  ]
end
```

## Example

`keypad` is a small GenServer to handle receiving messages from GPIO pins via [Circuits.GPIO](https://github.com/elixir-circuits/circuits_gpio) and then
reacting to them. `keypad` only implements the logic of reacting to pin state change and finding which
character it correlates to. It does not host any logic what to do with that value and expects a `handle_keypress/1`
function to be implemented to receive the deduced key presses.

It comes with some common predefined matricies of characters so assuming you are using the default row and column
GPIO pins, you can make a simple module like so:

```elixir
defmodule MyModule do
  use Keypad, size: :four_by_four

  @impl true
  def handle_keypress(key, _), do: IO.inspect(key, label: "KEYPRESS: )
end
```

Then in an iex session, start your keypad procss and start pressing buttons

```elixir
$ MyModule.start_link

# Press some buttons
KEYPRESS: 1
KEYPRESS: 5
...
```

For more complex configuration and examples, see the [configuration](CONFIGURATION.md) doc.