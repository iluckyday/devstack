FROM debian as builder

#COPY build.sh /tmp/
#RUN chmod +x /tmp/build.sh
#RUN /tmp/build.sh
RUN df -h
RUN free -h
RUN lscpu


#FROM scratch

#COPY --from=builder /tmp/devstack.cmp.img /devstack.cmp.img
