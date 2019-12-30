FROM debian as builder

#COPY build.sh /tmp/
#RUN chmod +x /tmp/build.sh
#RUN /tmp/build.sh
RUN busybox free -m


#FROM scratch

#COPY --from=builder /tmp/devstack.cmp.img /devstack.cmp.img
