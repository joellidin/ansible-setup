FROM ubuntu:focal as base
WORKDIR /usr/local/bin
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update
RUN apt-get upgrade -y 
RUN apt-get install -y software-properties-common curl git build-essential 
RUN apt-add-repository -y ppa:ansible/ansible
RUN apt-get update 
RUN apt-get install -y curl git sudo ansible build-essential 
RUN apt-get clean autoclean 
RUN apt-get autoremove --yes

FROM base as jlidin
ARG TAGS
RUN addgroup --gid 1000 jlidin
RUN adduser --gecos jlidin --uid 1000 --gid 1000 --disabled-password jlidin
RUN usermod -aG sudo jlidin
RUN passwd -d jlidin
USER jlidin
WORKDIR /home/jlidin

FROM jlidin
COPY --chown=jlidin:jlidin . .
# CMD ["sh", "-c", "ansible-playbook $TAGS local.yml"]
