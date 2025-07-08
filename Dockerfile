FROM ubuntu:noble AS base
WORKDIR /usr/local/bin
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get upgrade -y 
RUN apt-get install -y software-properties-common curl git build-essential 
RUN apt-add-repository -y ppa:ansible/ansible
RUN apt-get update 
RUN apt-get install -y curl git sudo ansible build-essential cron
RUN apt-get clean autoclean 
RUN apt-get autoremove --yes

FROM base AS jlidin
ARG TAGS
RUN addgroup --gid 1001 jlidin
RUN adduser --gecos jlidin --uid 1001 --gid 1001 --disabled-password jlidin
RUN usermod -aG sudo jlidin
RUN passwd -d jlidin
USER jlidin
WORKDIR /home/jlidin

FROM jlidin
COPY --chown=jlidin:jlidin . .
# CMD ["sh", "-c", "ansible-playbook $TAGS local.yml"]
