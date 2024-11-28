FROM zonemaster/engine:local AS build

RUN apk add --no-cache \
    make \
    perl-app-cpanminus \
    perl-json-xs \
    perl-lwp-protocol-https \
    perl-mojolicious \
    perl-test-deep \
    perl-test-differences \
    perl-try-tiny \
 && cpanm --notest --no-wget --from https://cpan.metacpan.org/ \
    JSON::Validator

ARG version

COPY ./Zonemaster-CLI-${version}.tar.gz ./Zonemaster-CLI-${version}.tar.gz

RUN cpanm --notest --no-wget \
    ./Zonemaster-CLI-${version}.tar.gz

FROM zonemaster/engine:local

RUN apk add --no-cache \
    perl-json-xs \
    perl-try-tiny

COPY --from=build /usr/local/bin/zonemaster-cli /usr/local/bin/zonemaster-cli
# Include all the Perl modules we built
COPY --from=build /usr/local/lib/perl5/site_perl /usr/local/lib/perl5/site_perl
COPY --from=build /usr/local/share/perl5/site_perl /usr/local/share/perl5/site_perl

USER nobody:nogroup

ENTRYPOINT [ "zonemaster-cli" ]

CMD [ "--help" ]
