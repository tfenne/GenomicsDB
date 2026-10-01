# Linux build toolchain for this fork: AlmaLinux 8 (glibc 2.28) with GCC 15, clang 21 and CMake 4
FROM almalinux:8
RUN dnf -y install gcc-toolset-15-gcc gcc-toolset-15-gcc-c++ gcc-toolset-15-binutils llvm-toolset \
      git make which patch diffutils file zlib-devel openssl-devel libcurl-devel libuuid-devel python3 \
      java-17-openjdk-devel autoconf automake libtool perl-IPC-Cmd perl-Time-Piece \
      && dnf -y module install maven:3.8 && dnf clean all
ARG CMAKE_VERSION=4.4.2
RUN curl -sfL https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-$(uname -m).tar.gz \
      | tar xz -C /opt && ln -s /opt/cmake-${CMAKE_VERSION}-linux-$(uname -m)/bin/* /usr/local/bin/
RUN git config --system safe.directory '*'
# clang uses GCC 15's libstdc++ rather than the system GCC 8's
RUN echo "--gcc-install-dir=/opt/rh/gcc-toolset-15/root/usr/lib/gcc/$(uname -m)-redhat-linux/15" | tee /usr/bin/clang.cfg > /usr/bin/clang++.cfg
