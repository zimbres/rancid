FROM ubuntu

ENV DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install git expect iputils-ping nano supervisor cron msmtp -y

RUN useradd -ms /bin/bash rancid
RUN usermod -a -G tty rancid

RUN mkdir /home/rancid/.ssh
COPY .msmtprc /home/rancid
COPY .ssh/id_rsa /home/rancid/.ssh
COPY .ssh/config /home/rancid/.ssh
COPY rancid /home/rancid/rancid
COPY .cloginrc /home/rancid
COPY .gitconfig /home/rancid
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chown rancid:rancid /home/rancid -R
RUN chmod 600 /home/rancid/.ssh/id_rsa
RUN chmod 600 /home/rancid/.cloginrc

USER rancid
RUN (crontab -l ; echo "0 */12 * * * /home/rancid/rancid/bin/rancid-run") | crontab
RUN (crontab -l ; echo "* * * * * find /home/rancid/rancid/var/logs/* -mtime +0 -exec rm -f {} \;") | crontab
USER root

WORKDIR /home/rancid
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
