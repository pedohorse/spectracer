{ lib, stdenv, zig, embree, glibc, libspng }:
stdenv.mkDerivation {
  pname = "spectracer";
  version = "0.0.1";

  src = ./.;

  buildInputs = [
    glibc.dev
    embree
    libspng.dev
  ];

  nativeBuildInputs = [
    zig.hook
  ];

  zigBuildFlags = [
    "-Doptimize=ReleaseFast"
  ];
}
