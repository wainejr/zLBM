# zLBM

LBM (lattice Boltzmann method) solver written in Zig for learning purposes.

The project is done by [Waine](https://github.com/wainejr/) and you can find the videos on its developing on his [YouTube](https://www.youtube.com/@waine_jr), in the [zLBM playlist](https://www.youtube.com/watch?v=BZobw0vnSHo&list=PL2WQTg3Tx5wO79IqfPwQhvgTqZsfIob9V).

## Building & Running

To build the project, make sure you have [Zig](https://ziglang.org/) installed.
The solver was developed and tested under version 0.13.0 and 0.14 on development.

After that, you can build the program running

```bash
zig build
```

And then run with

```bash
./zig-out/bin/zLBM
```

Or just run the project directly with

```bash
zig run src/main.zig
```
