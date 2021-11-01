FROM zonemaster/engine:local as build

RUN apk add --no-cache \
    # Only needed for Net::Interface
    build-base \
    perl-dev \
    perl-doc \
    make \
    # Compile-time dependencies
    perl-app-cpanminus \
    perl-module-install \
 && cpanm --no-wget \
    MooseX::Getopt \
    Text::Reflow

ARG version

COPY ./Zonemaster-CLI-${version}.tar.gz ./Zonemaster-CLI-${version}.tar.gz

RUN cpanm --no-wget \
    ./Zonemaster-CLI-${version}.tar.gz

FROM zonemaster/engine:local

COPY --from=build /usr/local/bin/zonemaster-cli /usr/local/bin/zonemaster-cli
# Include all the Perl modules we built
COPY --from=build /usr/local/lib/perl5/site_perl /usr/local/lib/perl5/site_perl
COPY --from=build /usr/local/share/perl5/site_perl /usr/local/share/perl5/site_perl

USER nobody:nogroup

ENTRYPOINT [ "zonemaster-cli" ]

CMD [ "--help" ]
