FROM vyos/vyos-build

# Copy configuration files
COPY config/config.boot /config/config.boot
COPY config/vyos.conf /etc/frr/vyos.conf

# Build VyOS image
RUN sudo /bin/bash -c 'source /opt/vyatta/etc/functions/script-template && \
    vyatta-build-setup-workspace && \
    vyatta-build-vyos && \
    vyatta-build-image'
