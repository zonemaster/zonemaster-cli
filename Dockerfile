FROM debian:bullseye-slim

RUN    apt-get -qq update \
    && apt-get -qq --no-install-recommends install \
         ldnsutils \
         libldns-dev \
         autoconf \
         automake \
         build-essential \
         cpanminus \
         libclone-perl \
         libdevel-checklib-perl \
         libfile-sharedir-perl \
         libfile-slurp-perl \
         libidn11-dev \
         libintl-perl \
         libio-socket-inet6-perl \
         libjson-pp-perl \
         liblist-moreutils-perl \
         liblocale-msgfmt-perl \
         libmail-rfc822-address-perl \
         libmodule-find-perl \
         libmodule-install-xsutil-perl \
         libmoose-perl \
         libnet-ip-perl \
         libpod-coverage-perl \
         libreadonly-xs-perl \
         libssl-dev \
         libtest-differences-perl \
         libtest-exception-perl \
         libtest-fatal-perl \
         libtest-pod-perl \
         libtext-csv-perl \
         libtool \
         m4 \
    && cpanm Module::Install Test::More \
    && cpanm --notest --configure-args="--no-internal-ldns" Zonemaster::LDNS \
    && cpanm --notest Zonemaster::Engine Zonemaster::CLI \
    && apt-get -qq purge \
         libldns-dev \
         autoconf \
         automake \
         build-essential \
         cpanminus \
         libssl-dev \
         libtool \
         m4 \
    && apt-get -qq --purge autoremove

CMD ["-h"]
ENTRYPOINT ["/usr/local/bin/zonemaster-cli"]
