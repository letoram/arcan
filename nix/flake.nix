{
  description = "arcan development environment";

  inputs = {
    nixpkgs.url = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
  }:
  let
    default_system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${default_system};
  in {
    devShell.${default_system} = pkgs.mkShell {
      nativeBuildInputs = with pkgs; [
        fossil
        luajit
        cmake
        gnumake
        pkg-config
        freetype.dev
        sqlite.dev
        mesa
        mesa.dev
        mesa_glu
        mesa_glu.dev
        openal
        SDL2
        SDL2.dev
        libxkbcommon
        libusb1
        libuvc
        libunwind
        libvlc
        libglvnd
        libglvnd.dev
        eglexternalplatform
        ffmpeg
        espeak
        mupdf
        zlib
        libjpeg
        harfbuzz
        jbig2dec
        openjpeg_2
        gumbo
        glib
        file
        tesseract
        leptonica
        libvncserver
        wayland
        wayland-protocols
        libffi
        xorg.xcbutil
        xorg.xcbutilwm
        xorg.xauth
      ];

      hardeningDisable = [ "all" ];
    };
  };
}

