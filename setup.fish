#!/usr/bin/env fish

set options 'j/jobs=!_validate_int --min 1'
argparse --name=setup_cross_compiler $options -- $argv
or exit 1


if not set -q _flag_jobs || not set -q _flag_j
  echo "-j/--jobs flag required"
  exit 1
end

set --show _flag_jobs
set j "$_flag_jobs"

set ARCHS x86_64 aarch64 riscv64
set PREFIX "$HOME/opt/cross"
set BUILD_DIR "$HOME/cross-build/"
set TARGET elf
set APPLY_REDZONE_PATCH true


set GCC_VERSION "13.2.0"
set GCC_DOWNLOAD_URL "https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.gz"
set GCC_DOWNLOAD_SIG_URL "$GCC_DOWNLOAD_URL.sig"
set GCC_FILE "gcc-$GCC_VERSION.tar.gz"
set GCC_DIR "gcc-$GCC_VERSION"

set BINUTILS_VERSION "2.41"
set BINUTILS_DOWNLOAD_URL "https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.gz"
set BINUTILS_DOWNLOAD_SIG_URL "$BINUTILS_DOWNLOAD_URL.sig"
set BINUTILS_FILE "binutils-$BINUTILS_VERSION.tar.gz"
set BINUTILS_DIR "binutils-$BINUTILS_VERSION"

function check_for_command
  printf "Checking for command \033[32m$argv[1]\033[0m\n"
  if not type -q $argv[1]
    printf "\033[31mERROR: Command $argv[1] not found. Please install it.\n"
    exit 1
  end
end

function line 
  for i in (seq 1 80)
    printf "-"
  end
  echo
end

function print_configuration
  printf "Configuration:\n\n"

  line
  echo

  printf "ARCHS\t\t\t= $ARCHS\n"
  printf "PREFIX\t\t\t= $PREFIX\n"
  printf "BUILD_DIR\t\t= $BUILD_DIR\t# Also acts as download dir\n"
  printf "TARGET\t\t\t= $TARGET\n"
  printf "APPLY_REDZONE_PATCH\t= $APPLY_REDZONE_PATCH\t\t\t\t# Only for x86_64\n"
  printf "jobs\t\t\t= $j\n"

  echo

  printf "GCC_VERSION\t\t= $GCC_VERSION\n"
  printf "BINUTILS_VERSION\t= $BINUTILS_VERSION\n"

  echo
  
  printf "Installing GCC $GCC_VERSION at $GCC_DOWNLOAD_URL with signature $GCC_DOWNLOAD_SIG_URL\n"
  printf "Installing binutils $BINUTILS_VERSION at $BINUTILS_DOWNLOAD_URL with signature $BINUTILS_DOWNLOAD_SIG_URL\n"

  echo
  line
end

function create_directory
  printf "Creating directory \033[32m$argv[1]\n\033[0m"
  mkdir -p $argv[1]
end

function create_skel_dirs

  create_directory $PREFIX
  create_directory $BUILD_DIR

end


function download_files
  printf "Downloading Files\n\n"
  # GCC
  printf "GCC Archive\n"
  curl -L# $GCC_DOWNLOAD_URL -o $BUILD_DIR/gcc-$GCC_VERSION.tar.gz
  printf "GCC Signature\n"
  curl -L# $GCC_DOWNLOAD_SIG_URL -o $BUILD_DIR/gcc-$GCC_VERSION.tar.gz.sig

  # Binutils
  printf "Binutils Archive\n"
  curl -L# $BINUTILS_DOWNLOAD_URL -o $BUILD_DIR/binutils-$BINUTILS_VERSION.tar.gz
  printf "Binutils Signature\n"
  curl -L# $BINUTILS_DOWNLOAD_SIG_URL -o $BUILD_DIR/binutils-$BINUTILS_VERSION.tar.gz.sig

  # Keyring
  printf "Keyring for signature verification\n"
  curl -L# "https://ftp.gnu.org/gnu/gnu-keyring.gpg" -o $BUILD_DIR/gnu-keyring.gpg
end

function verify_files
  printf "Verifying Files\n"
  printf "Importing gpg keys, writing to gpg-import.log\n"

  gpg --import $BUILD_DIR/gnu-keyring.gpg &> gpg-import.log

  printf "Finished importing gpg keys\n"
  printf "Verifying GCC Archive\n"
  echo

  gpg --verify $BUILD_DIR/gcc-$GCC_VERSION.tar.gz.sig

  if test "$status" -ne 0
    printf "ERROR:\033[31m GCC File verification failed. Please try to rerun the script or report the error."
    exit 1
  end

  echo

  printf "GCC Archive verifyed successfully\n"

  printf "Verifying binutils Archive\n"
  echo

  gpg --verify $BUILD_DIR/binutils-$BINUTILS_VERSION.tar.gz.sig

  if test "$status" -ne 0
    printf "ERROR:\033[31m GCC File verification failed. Please try to rerun the script or report the error."
    exit 1
  end

  echo

  printf "Binutils Archive verifyed successfully\n"

end

function extract_files
  printf "Extracting Files\n"

  create_directory $BUILD_DIR/$GCC_DIR
  tar -xf $BUILD_DIR/$GCC_FILE -C $BUILD_DIR

  create_directory $BUILD_DIR/$BINUTILS_DIR
  tar -xf $BUILD_DIR/$BINUTILS_FILE -C $BUILD_DIR
end

function configure
  set -f dir $argv[1]
  set -f conf_pos $argv[2]
  set -f conf_args

  for i in (seq (math (count $argv) - 2))
    set -a conf_args $argv[(math $i + 2)]
  end
  
  echo "Configure directory: $dir"
  echo "With args: $conf_args"
  
  set cwd (pwd)

  cd $dir
  echo "Entered directory $dir"
  echo "Running ./configure $conf_args"

  echo
  eval $conf_pos/configure $conf_args
  echo

  echo "Exiting dir"
  cd $cwd
end

function build
  set -f dir $argv[1]
  set -f jobs $argv[2]
  set -f target $argv[3]

  echo "Building directory: $dir"
  echo "With target: $target"
  echo "And $jobs jobs"

  set cwd (pwd)

  cd $dir
  echo "Entered directory $dir"
  echo "Running make $target"
  
  echo
  make $target -j$jobs
  echo

  echo "Exiting dir"
  cd $cwd
end

function build_binutils

  set -f target $argv[1]
  set -f jobs $argv[2]

  set -f bu_build_dir $BUILD_DIR/$BINUTILS_DIR-build-$target

  echo "Building binutils for target: $target with $jobs jobs at $bu_build_dir"

  create_directory $bu_build_dir
  configure $bu_build_dir $BUILD_DIR/$BINUTILS_DIR --target=$target --prefix="$PREFIX" --with-sysroot --disable-nls --disable-werror
  build $bu_build_dir $jobs
  build $bu_build_dir 1 install
end

function build_gcc
  set -f target $argv[1]
  set -f jobs $argv[2]

  set -f gcc_build_dir $BUILD_DIR/$GCC_DIR-build-$target

  echo "Building gcc for target: $target with $jobs jobs at $gcc_build_dir"
  
  create_directory $gcc_build_dir
  configure $gcc_build_dir $BUILD_DIR/$GCC_DIR --target=$target --prefix="$PREFIX" --disable-nls --enable-languages=c,c++ --without-headers
  build $gcc_build_dir $jobs all-gcc
  build $gcc_build_dir $jobs all-target-libgcc
  build $gcc_build_dir 1 install-gcc 
  build $gcc_build_dir 1 install-target-libgcc
end

echo
printf "Setup Cross Compilers\n"
printf "A automatic script to install Cross Compilers for x86_64, aarch64 and riscv64\n"

echo
print_configuration $j
echo

check_for_command gpg
check_for_command curl
check_for_command make
check_for_command tar

echo

create_skel_dirs
echo
download_files
verify_files
extract_files

set targets x86_64 aarch64 riscv64
for btarget in $targets

  build_binutils $btarget-$TARGET $j
  build_gcc $btarget-$TARGET $j

end

