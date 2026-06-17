{
  stdenv,
  lib,
  fetchFromGitHub,
  bash,
  cmake,
  pkg-config,
  cfitsio,
  libusb1,
  kmod,
  zlib,
  boost,
  liberfa,
  libev,
  libnova,
  curl,
  libjpeg,
  gsl,
  fftw,
  gtest,
  udevCheckHook,
  versionCheckHook,
  indi-full,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "indilib";
  version = "2.2.3.1";

  src = fetchFromGitHub {
    owner = "indilib";
    repo = "indi";
    rev = "v${finalAttrs.version}";
    hash = "sha256-WSia7uYFXwuSJ1yxOEs6/55nUPPywaUfMxIHMZ+2/wg=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  nativeInstallCheckInputs = [
    versionCheckHook
    udevCheckHook
  ];

  buildInputs = [
    curl
    cfitsio
    libev
    libusb1
    zlib
    boost
    libnova
    libjpeg
    liberfa
    gsl
    fftw
  ];

  cmakeFlags = [
    "-DCMAKE_INSTALL_LIBDIR=lib"
    "-DUDEVRULES_INSTALL_DIR=lib/udev/rules.d"
  ]
  ++ lib.optional finalAttrs.finalPackage.doCheck [
    "-DINDI_BUILD_UNITTESTS=ON"
    "-DINDI_BUILD_INTEGTESTS=ON"
  ];

  checkInputs = [ gtest ];

  # GCC 15 promotes a number of warnings (stringop-truncation/-overread,
  # free-nonheap-object, ...) to errors that upstream's -Werror then fails on.
  # These are mostly false positives, so just keep them as warnings.
  env.NIX_CFLAGS_COMPILE = "-Wno-error";

  # tests seem to be broken on darwin
  doCheck = !stdenv.hostPlatform.isDarwin;
  doInstallCheck = true;

  # Upstream's v2.2.3.1 hotfix retag never bumped the internal version, so
  # `indiserver --version` still reports the 3-component base ("2.2.3"). Point
  # versionCheckHook at that base version (derived from `version`, so a future
  # bump needs no change here) instead of the full tag.
  preVersionCheck = ''
    version=${lib.versions.majorMinor finalAttrs.version}.${lib.versions.patch finalAttrs.version}
  '';

  # Socket address collisions between tests
  enableParallelChecking = false;

  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    for f in $out/lib/udev/rules.d/*.rules
    do
      substituteInPlace $f --replace-quiet "/bin/sh" "${bash}/bin/sh" \
                           --replace-quiet "/sbin/modprobe" "${kmod}/sbin/modprobe"
    done
  '';

  passthru.tests = {
    # make sure 3rd party drivers compile with this indilib
    indi-full = indi-full.override {
      indilib = finalAttrs.finalPackage;
    };
  };

  meta = {
    homepage = "https://www.indilib.org/";
    description = "Implementation of the INDI protocol for POSIX operating systems";
    changelog = "https://github.com/indilib/indi/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.lgpl2Plus;
    mainProgram = "indiserver";
    maintainers = with lib.maintainers; [
      sheepforce
      returntoreality
    ];
    platforms = lib.platforms.unix;
  };
})
