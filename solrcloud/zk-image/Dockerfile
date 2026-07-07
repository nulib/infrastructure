ARG ZK_VERSION=3.9
FROM zookeeper:${ZK_VERSION}
RUN <<__EOF__
  apt-get update
  apt-get install -y awscli
  apt-get clean
  rm -rf /var/lib/apt/lists/*
__EOF__
COPY docker-entrypoint.sh /docker-entrypoint.sh
ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["zkServer.sh", "start-foreground"]