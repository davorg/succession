FROM perl:latest
LABEL maintainer="dave@perlhacks.org"

RUN apt-get install openssl libssl-dev libz-dev libexpat1-dev
RUN curl -L http://cpanmin.us | perl - App::cpanminus
RUN cpanm Carton Starman

RUN git clone https://github.com/davorg/succession.git
RUN cd succession && carton install --deployment

EXPOSE 1701

WORKDIR succession
CMD carton exec starman --port 1701 Succession/bin/app.psgi
