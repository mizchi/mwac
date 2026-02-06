# mwac

A WebAssembly Component Model composition tool written in [MoonBit](https://www.moonbitlang.com/).

Parses [WAC (WebAssembly Compositions)](https://github.com/bytecodealliance/wac) `.wac` scripts and composes multiple WebAssembly Components into a single component via plug/compose.

## Features

- `.wac` script parsing and resolution
- Component Model binary (`.wasm`) parsing (import/export extraction, type analysis)
- `plug` — satisfy a component's imports with another component's exports
- `compose` — compose multiple components based on a WAC script
- Dead Code Elimination (prune unused instances)
- WIT interface type compatibility checking

## Project Structure

```
src/
├── component/    # Component Model binary parser, plug, encoder
└── composer/     # WAC parser, resolver, composer, DCE

examples/
├── hello/        # Single component example
├── compose/      # Multi-component composition example
├── core-module/  # Core Module plug example
└── wac/          # WAC script example
```

## WAC Script Example

```wac
package example:composition;

let hello = new example:hello {};
let greeter = new example:greeter {
  hello: hello.hello,
};

export greeter.greet;
```

## Development

```bash
just           # check + test
just fmt       # format code
just check     # type check
just test      # run tests
just run       # run main
```

## Dependencies

- [MoonBit](https://www.moonbitlang.com/) toolchain
- [mizchi/wit](https://mooncakes.io/docs/#/mizchi/wit/) — WIT parser

## License

Apache-2.0
