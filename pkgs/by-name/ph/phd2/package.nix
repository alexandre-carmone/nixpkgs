{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  wrapGAppsHook3,
  cfitsio,
  curl,
  eigen_3_4_0,
  gettext,
  glib,
  gtest,
  gtk3,
  indilib,
  libnova,
  libusb1,
  opencv,
  wxwidgets_3_2,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "phd2";
  version = "2.6.14";

  src = fetchFromGitHub {
    owner = "OpenPHDGuiding";
    repo = "phd2";
    tag = "v${finalAttrs.version}";
    hash = "sha256-+sDp/D0ovhmGAC2a9EtsN2nkt+1Yw/OaR/LJzS/9Ulg=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    wrapGAppsHook3
  ];

  buildInputs = [
    cfitsio
    curl
    eigen_3_4_0
    gettext
    glib
    gtest
    gtk3
    indilib
    libnova
    libusb1
    opencv
    wxwidgets_3_2
    zlib
  ];

  cmakeFlags = [
    "-DCMAKE_CXX_STANDARD=17" # needed for gtest
    "-DOPENSOURCE_ONLY=1"
    "-DUSE_SYSTEM_CFITSIO=ON"
    "-DUSE_SYSTEM_LIBUSB=ON"
    "-DUSE_SYSTEM_EIGEN3=ON"
    "-DUSE_SYSTEM_GTEST=ON"
    "-DUSE_SYSTEM_LIBINDI=ON"
  ];

  # Fix broken wrapped name scheme by moving wrapped binary to where wrapper expects it
  postFixup = ''
    mv $out/bin/.phd2.bin-wrapped $out/bin/.phd2-wrapped.bin
  '';

  meta = {
    homepage = "https://openphdguiding.org/";
    description = "Telescope auto-guidance application";
    changelog = "https://github.com/OpenPHDGuiding/phd2/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.bsd3;
    maintainers = with lib.maintainers; [
      returntoreality
    ];
    platforms = lib.platforms.linux;
  };
})
