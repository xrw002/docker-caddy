FROM ubuntu:16.04
LABEL maintainer="liudanking@gmail.com"
RUN apt-get update
RUN set -x  \
	&& apt-get install curl -y \
	&& curl https://getcaddy.com | bash -s personal && which caddy
