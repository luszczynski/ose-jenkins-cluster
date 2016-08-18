#!/bin/bash

master_username=${JENKINS_USERNAME:-"admin"}
master_password=${JENKINS_PASSWORD:-"password"}
slave_executors=${EXECUTORS:-"1"}



# If JENKINS_SECRET and JENKINS_JNLP_URL are present, run JNLP slave
if [ ! -z $JENKINS_SECRET ] && [ ! -z $JENKINS_JNLP_URL ]; then

    echo "Running Jenkins JNLP Slave...."
	JAR=`ls -1 /opt/jenkins-slave/bin/slave.jar | tail -n 1`

	# if -tunnel is not provided try env vars
	if [[ "$@" != *"-tunnel "* ]]; then
		if [[ ! -z "$JENKINS_TUNNEL" ]]; then
			TUNNEL="-tunnel $JENKINS_TUNNEL"
		fi
	fi

	if [[ ! -z "$JENKINS_URL" ]]; then
		URL="-url $JENKINS_URL"
	fi

	exec java $JAVA_OPTS -cp $JAR hudson.remoting.jnlp.Main -headless $TUNNEL $URL -jar-cache $HOME "$@"

elif [[ $# -lt 1 ]] || [[ "$1" == "-"* ]]; then

  echo "Running Jenkins Swarm Plugin...."

  # jenkins swarm slave
  JAR=`ls -1 /opt/jenkins-slave/bin/swarm-client-*.jar | tail -n 1`

  export no_proxy="$no_proxy,${JENKINS_SERVICE_HOST},${JENKINS_SLAVE_SERVICE_HOST}"
  export NO_PROXY="$NO_PROXY,${JENKINS_SERVICE_HOST},${JENKINS_SLAVE_SERVICE_HOST}"

  if [[ "$@" != *"-master "* ]] && [ ! -z "$JENKINS_PORT_8080_TCP_ADDR" ]; then
	PARAMS="-master http://${JENKINS_SERVICE_HOST}:${JENKINS_SERVICE_PORT}${JENKINS_CONTEXT_PATH} -tunnel ${JENKINS_SERVICE_HOST}:${JENKINS_SERVICE_PORT_REMOTING} -username ${master_username} -password ${master_password} -executors ${slave_executors}"
  fi

  proxyHost=$(echo $http_proxy | sed 's/http:\/\///g'| cut -d: -f1)
  proxyPort=$(echo $http_proxy | sed 's/http:\/\///g'| cut -d: -f2)
  PROXY_PARAMS="-Dhttp.proxyHost=$proxyHost -Dhttp.proxyPort=$proxyPort"
  noProxy=$(echo $no_proxy | sed 's/,/|/g')
  PROXY_PARAMS="${PROXY_PARAMS} -Dhttp.nonProxyHosts=$noProxy|${JENKINS_SERVICE_HOST}|${JENKINS_SLAVE_SERVICE_HOST}"

  echo "Running java ${PROXY_PARAMS} $JAVA_OPTS -jar $JAR -fsroot $HOME $PARAMS \"$@\""
  exec java ${PROXY_PARAMS} $JAVA_OPTS -jar $JAR -fsroot $HOME $PARAMS "$@" > /tmp/tmp.log 2>&1 &

  pid_last_command=$(echo $!)

  until grep -qv "Setting up slave:" /tmp/tmp.log; do
    echo "Sleeping..."
    sleep 1
  done

  node=$(grep "Setting up slave:" /tmp/tmp.log | cut -d: -f3 | tr -d ' ')
  kill $pid_last_command

  exec java -jar /opt/jenkins-slave/bin/slave.jar -jnlpUrl http://$JENKINS_SERVICE_HOST:$JENKINS_SERVICE_PORT/computer/$node/slave-agent.jnlp  -jnlpCredentials admin:password

fi
