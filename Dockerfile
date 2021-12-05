FROM ghcr.io/mattblack85/astrobase:0.1.0 AS builder

RUN pacman -Syu --noconfirm

# Set the global versions to checkout from git to build
ENV INDI_VERSION=v1.9.3
ENV KSTARS_VERSION=stable-3.5.6

# Make a bag where all the compile executable will be stored
RUN mkdir /tmp/final

# Move to build  where Kstars, indi and GSC will be built
WORKDIR /tmp/build

# Clone the source code
RUN git clone https://invent.kde.org/education/kstars.git
RUN git clone https://github.com/indilib/indi.git
RUN git clone https://github.com/indilib/indi-3rdparty.git

# Checkout the right version
RUN cd kstars && git checkout $KSTARS_VERSION
RUN cd indi && git checkout $INDI_VERSION
RUN cd indi-3rdparty && git checkout $INDI_VERSION

# Make a folder where indi-core will be built, files will be installed into /tmp/final
RUN mkdir -p /tmp/build/indi-core
WORKDIR /tmp/build/indi-core
RUN cmake -DCMAKE_INSTALL_PREFIX=/tmp/final -DCMAKE_BUILD_TYPE=Debug /tmp/build/indi
RUN make -j $(nproc)
RUN make install

# Build ALL extra indi drivers    
RUN mkdir -p /tmp/build/indi-extra
WORKDIR /tmp/build/indi-extra
RUN cmake -DCMAKE_INSTALL_PREFIX=/tmp/final -DCMAKE_BUILD_TYPE=Debug /tmp/build/indi-3rdparty
RUN make -j $(nproc)
RUN make install

USER root
RUN mkdir -p /tmp/build/kstars
WORKDIR /tmp/build/kstars
RUN ls -lsa /tmp/final/include/libindi
RUN cmake -DCMAKE_INSTALL_PREFIX=/tmp/final -DCMAKE_BUILD_TYPE=RelWithDebInfo ../kstars -DCMAKE_CXX_FLAGS="-I /tmp/final/include"
RUN make -j $(nproc)
RUN make install

WORKDIR /tmp/final
RUN ls -ls .

FROM archlinux:latest

RUN pacman -Syu --noconfirm

RUN pacman -S cfitsio fftw gsl \
    libjpeg-turbo libnova libtheora libusb boost \
    libraw libgphoto2 libftdi libdc1394 libavc1394 \
    ffmpeg gpsd breeze-icons hicolor-icon-theme knewstuff \
    knotifyconfig kplotting qt5-datavis3d qt5-quickcontrols \
    qt5-websockets qtkeychain stellarsolver \
    kf5 eigen --noconfirm

RUN useradd -ms /bin/bash astro
USER astro
WORKDIR /home/astro
RUN mkdir -p .local/share/kstars

COPY --from=builder /tmp/final/bin/ /usr/bin
COPY --from=builder /tmp/final/share/ /usr/share
COPY --from=builder /tmp/final/lib/ /usr/lib
COPY --from=builder /tmp/final/include/ /usr/include
COPY --from=builder /tmp/build/gsc/pkg/gsc/usr/share/GSC/ /usr/share/
COPY --from=builder /tmp/build/gsc/pkg/gsc/usr/share/GSC/bin/ /usr/bin/
COPY --from=builder /tmp/build/gsc/gsc-1.2-4-x86_64.pkg.tar.zst /tmp/
COPY --from=builder /etc/astrometry.cfg .
COPY --from=builder /tmp/build/astrometry.net/astrometry*.zst /tmp/
COPY --from=builder /tmp/build/python-astropy/python-astropy*.zst /tmp/
COPY --from=builder /tmp/build/python-pyerfa/python-pyerfa*.zst /tmp/
COPY --from=builder /tmp/build/erfa/erfa*.zst /tmp/

USER root
RUN pacman -U /tmp/gsc-1.2-4-x86_64.pkg.tar.zst --noconfirm
RUN pacman -U /tmp/erfa*.zst --noconfirm
RUN pacman -U /tmp/python-pyerfa*.zst --noconfirm
RUN pacman -U /tmp/python-astropy*.zst --noconfirm
RUN pacman -U /tmp/astrometry.net-0.85-1-x86_64.pkg.tar.zst --noconfirm
RUN rm /tmp/*.zst
USER astro

CMD ["/usr/bin/kstars"]
