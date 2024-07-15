FROM ubuntu:noble

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update
RUN apt install -y git expect iputils-ping nano msmtp tzdata curl jq && rm -rf /var/lib/apt/lists/*

RUN useradd -ms /bin/bash rancid
RUN usermod -a -G tty rancid

RUN mkdir /home/rancid/.ssh
COPY .msmtprc /home/rancid
COPY .ssh/id_rsa /home/rancid/.ssh
COPY .ssh/config /home/rancid/.ssh
COPY rancid /home/rancid/rancid
COPY .cloginrc /home/rancid
COPY .gitconfig /home/rancid
COPY run.sh /home/rancid

RUN chown rancid:rancid /home/rancid -R
RUN chmod +x /home/rancid/rancid/bin/*
RUN chmod +x /home/rancid/run.sh
RUN chmod 600 /home/rancid/.ssh/id_rsa
RUN chmod 600 /home/rancid/.cloginrc

USER rancid

WORKDIR /home/rancid
CMD ["/home/rancid/run.sh"]
