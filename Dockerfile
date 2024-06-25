FROM zonemaster/engine:local as build

RUN apk add --no-cache \
    build-base \
    make \
    perl-app-cpanminus \
    perl-cpan-meta-check \
    perl-data-dump \
    perl-dev \
    perl-doc \
    perl-json-xs \
    perl-lwp-protocol-https \
    perl-module-build \
    perl-module-build-tiny \
    perl-module-install \
    perl-moose \
    perl-namespace-autoclean \
    perl-params-validate \
    perl-path-tiny \
    perl-test-deep \
    perl-test-needs \
 && cpanm --no-wget --from https://cpan.metacpan.org/ \
    MooseX::Getopt

ARG version

COPY ./Zonemaster-CLI-${version}.tar.gz ./Zonemaster-CLI-${version}.tar.gz

RUN cpanm --no-wget \
    ./Zonemaster-CLI-${version}.tar.gz

FROM zonemaster/engine:local

RUN apk add --no-cache \
    perl-namespace-autoclean \
    perl-params-validate \
    perl-json-xs \
    perl-moose

COPY --from=build /usr/local/bin/zonemaster-cli /usr/local/bin/zonemaster-cli
# Include all the Perl modules we built
COPY --from=build /usr/local/lib/perl5/site_perl /usr/local/lib/perl5/site_perl
COPY --from=build /usr/local/share/perl5/site_perl /usr/local/share/perl5/site_perl

USER nobody:nogroup

ENTRYPOINT [ "zonemaster-cli" ]

CMD [ "--help" ]
