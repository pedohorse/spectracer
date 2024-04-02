{
  description = "simple embree-based backwards path-tracer that traces different frequencies separately";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system} = rec {
      spectracer = pkgs.callPackage ./default.nix {};
      default = spectracer;
    };
  };
}
