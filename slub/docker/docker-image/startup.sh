#!/bin/bash
cat /id_rsa >> /.ssh/id_rsa

# removes read/write/execute permissions from group and others, but preserves whatever permissions the owner had
chmod go-rwx /.ssh/*

# Add ocrd manager as global known_hosts if env exist
if [ -n "${OCRD_MANAGER%:*}" ]; then
	ssh-keygen -R ${OCRD_MANAGER%:*} -f /etc/ssh/ssh_known_hosts
	ssh-keyscan -H ${OCRD_MANAGER%:*} >> /etc/ssh/ssh_known_hosts
fi

# Place environment db variables
/bin/sed -i "s,\(jdbc:mysql://\)[^/]*\(/.*\),\1${KITODO_DB_HOST}:${KITODO_DB_PORT}\2," ${CATALINA_HOME}/webapps/kitodo/WEB-INF/classes/hibernate.cfg.xml
/bin/sed -i "s/kitodo?useSSL=false/${KITODO_DB_NAME}?useSSL=false\&amp;allowPublicKeyRetrieval=true/g" ${CATALINA_HOME}/webapps/kitodo/WEB-INF/classes/hibernate.cfg.xml
/bin/sed -i "s/hibernate.connection.username\">kitodo/hibernate.connection.username\">${KITODO_DB_USER}/g" ${CATALINA_HOME}/webapps/kitodo/WEB-INF/classes/hibernate.cfg.xml
/bin/sed -i "s/hibernate.connection.password\">kitodo/hibernate.connection.password\">${KITODO_DB_PASSWORD}/g" ${CATALINA_HOME}/webapps/kitodo/WEB-INF/classes/hibernate.cfg.xml

# Place environment es variables
/bin/sed -i "s,^\(elasticsearch.host\)=.*,\1=${KITODO_ES_HOST}," ${CATALINA_HOME}/webapps/kitodo/WEB-INF/classes/kitodo_config.properties

# Place environment mq variables
/bin/sed -i "s/localhost:61616/${KITODO_MQ_HOST}:${KITODO_MQ_PORT}/g" ${CATALINA_HOME}/webapps/kitodo/WEB-INF/classes/kitodo_config.properties
/bin/sed -i "s/#activeMQ.hostURL=/activeMQ.hostURL=/g" ${CATALINA_HOME}/webapps/kitodo/WEB-INF/classes/kitodo_config.properties
/bin/sed -i "s/#activeMQ.results.topic=/activeMQ.results.topic=/g" ${CATALINA_HOME}/webapps/kitodo/WEB-INF/classes/kitodo_config.properties
/bin/sed -i "s/#activeMQ.results.timeToLive=/activeMQ.results.timeToLive=/g" ${CATALINA_HOME}/webapps/kitodo/WEB-INF/classes/kitodo_config.properties
/bin/sed -i "s/#activeMQ.finalizeStep.queue=/activeMQ.finalizeStep.queue=/g" ${CATALINA_HOME}/webapps/kitodo/WEB-INF/classes/kitodo_config.properties

# Replace imklog to prevent starting problems of rsyslog
/bin/sed -i '/imklog/s/^/#/' /etc/rsyslog.conf

# Add tomcat logging to syslog on line 23
/bin/sed -i '23i module(load="imfile" PollingInterval="10")' /etc/rsyslog.conf


if [ -z "$(ls -A /usr/local/kitodo)" ]; then
   cp -R /tmp/kitodo/kitodo-config-modules/. /usr/local/kitodo/
fi

echo "Wait for database container."
/tmp/wait-for-it.sh -t 0 ${KITODO_DB_HOST}:${KITODO_DB_PORT}

echo "Initalize database."
echo "SELECT 1 FROM user LIMIT 1;" \
    | mysql -h "${KITODO_DB_HOST}" -P "${KITODO_DB_PORT}" -u ${KITODO_DB_USER} --password=${KITODO_DB_PASSWORD} ${KITODO_DB_NAME} >/dev/null 2>&1 \
    || mysql -h "${KITODO_DB_HOST}" -P "${KITODO_DB_PORT}" -u ${KITODO_DB_USER} --password=${KITODO_DB_PASSWORD} ${KITODO_DB_NAME} < /tmp/kitodo/kitodo.sql

echo "Starting rsyslog."
service rsyslog start

sleep 2

echo "Starting tomcat."
/usr/local/tomcat/bin/catalina.sh start 

tail -f /var/log/syslog