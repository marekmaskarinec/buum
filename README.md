# buum 💣

Buum (short for build.um) is a declarative cross platform build system designed
for Umka programs and libraries.

```go
import "bu.um"

fn build(b: ^bu::Build) {
  b.addModule("hello.um").install()
}
```

## Downloads

Precompiled binaries can be downloaded from CI artifacts:

* [linux](https://nightly.link/marekmaskarinec/buum/workflows/build/master/linux.zip)
* [windows](https://nightly.link/marekmaskarinec/buum/workflows/build/master/windows.zip)

## Usage

Proper usage guide is work in progress. You can refer to the usage in
[tophat2d](https://github.com/tophat2d/tophat/blob/main/build.um) or
[mmul](https://github.com/mmul/blob/master/build.um).

* [API Documentation](https://mmq.cz/dl/buum.html)

## Compiling

To compile buum you first need to download the correct Zig release. The release
should be the same version as you installation of Zig and platform for which
you are planning to compile. For example when compiling with Zig 0.14.1 for x86_64
linux, use this command:

```
curl https://ziglang.org/download/0.14.1/zig-x86_64-linux-0.14.1.tar.xz -o src/zig-x86_64-linux-0.14.1.tar.xz
```

After downloading the proper release, buum can be built as any other Zig program:

```
zig build
```

The results are in the `zig-out/bin` directory.

## License

The project is licensed under MIT/Unlicense, whichever you choose. See
[LICENSE](LICENSE) in repo root for more info.
