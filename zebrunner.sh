#!/bin/bash

  print_banner() {
  echo "
███████╗███████╗██████╗ ██████╗ ██╗   ██╗███╗   ██╗███╗   ██╗███████╗██████╗      ██████╗███████╗
╚══███╔╝██╔════╝██╔══██╗██╔══██╗██║   ██║████╗  ██║████╗  ██║██╔════╝██╔══██╗    ██╔════╝██╔════╝
  ███╔╝ █████╗  ██████╔╝██████╔╝██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██████╔╝    ██║     █████╗  
 ███╔╝  ██╔══╝  ██╔══██╗██╔══██╗██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██╔══██╗    ██║     ██╔══╝  
███████╗███████╗██████╔╝██║  ██║╚██████╔╝██║ ╚████║██║ ╚████║███████╗██║  ██║    ╚██████╗███████╗
╚══════╝╚══════╝╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝     ╚═════╝╚══════╝
"

  }

  setup() {
    print_banner

    # load default interactive installer settings
    source backup/settings.env.original

    # load ./backup/settings.env if exist to declare ZBR* vars from previous run!
    if [[ -f backup/settings.env ]]; then
      source backup/settings.env
    fi

    export ZBR_INSTALLER=1
    export ZBR_VERSION=1.7
    set_global_settings

    cp nginx/conf.d/default.conf.original nginx/conf.d/default.conf

    export ZBR_INFRA_HOST=$ZBR_HOSTNAME

    sed -i 's/server_name localhost/server_name '$ZBR_HOSTNAME'/g' ./nginx/conf.d/default.conf
    sed -i 's/listen 80/listen '$ZBR_PORT'/g' ./nginx/conf.d/default.conf

    # Reporting is obligatory component now. But to be able to disable it we can register REPORTING_DISABLED=1 env variable before setup
    if [[ $ZBR_REPORTING_ENABLED -eq 1 && -z $REPORTING_DISABLED ]]; then
      set_reporting_settings
      reporting/zebrunner.sh setup
    else
      # explicitly disable reporting and minio as it was disabled by engineer via REPORTING_DISABLED env var
      export ZBR_REPORTING_ENABLED=0
      disableLayer "reporting"
      disableLayer "reporting/minio-storage"
    fi

    enableLayer "sonarqube" "Use embedded SonarQube to organize static code analysis and guiding your team?" "$ZBR_SONARQUBE_ENABLED"
    export ZBR_SONARQUBE_ENABLED=$?

    # jenkins after sonar to detect and put valid SONAR_URL value
    enableLayer "jenkins" "Use embedded Jenkins as recommended CI tool?" "$ZBR_JENKINS_ENABLED"
    export ZBR_JENKINS_ENABLED=$?

    enableLayer "selenoid" "Use embedded Web Selenium Hub for testing on chrome, firefox, opera and MicrosoftEdge browsers?" "$ZBR_SELENOID_ENABLED"
    export ZBR_SELENOID_ENABLED=$?

    enableLayer "mcloud" "Use embedded Mobile Device Farm and Selenium/Appium Hub for testing on Android, iOS, AppleTV etc devices?" "$ZBR_MCLOUD_ENABLED"
    export ZBR_MCLOUD_ENABLED=$?

    if [[ $ZBR_SONARQUBE_ENABLED -eq 1 ]]; then
      sonarqube/zebrunner.sh setup
      export ZBR_SONAR_URL=$ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/sonarqube
    fi

    if [[ $ZBR_JENKINS_ENABLED -eq 1 ]]; then
      jenkins/zebrunner.sh setup
    fi

    if [[ $ZBR_MCLOUD_ENABLED -eq 1 && $ZBR_REPORTING_ENABLED -eq 0 ]] || [[ $ZBR_SELENOID_ENABLED -eq 1 && $ZBR_REPORTING_ENABLED -eq 0 ]]; then
      set_aws_storage_settings
    fi

    if [[ $ZBR_MCLOUD_ENABLED -eq 1 ]]; then
      mcloud/zebrunner.sh setup
    fi

    if [[ $ZBR_JENKINS_ENABLED -eq 1 && $ZBR_REPORTING_ENABLED -eq 1 ]]; then
      # update reporting-jenkins integration vars
      sed -i "s#JENKINS_ENABLED=false#JENKINS_ENABLED=true#g" reporting/configuration/reporting-service/variables.env
      sed -i "s#JENKINS_URL=#JENKINS_URL=$ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/jenkins#g" reporting/configuration/reporting-service/variables.env
    fi

    if [[ $ZBR_MCLOUD_ENABLED -eq 1 && $ZBR_REPORTING_ENABLED -eq 1 ]]; then
      # update reporting-mcloud integration vars
      sed -i "s#MCLOUD_ENABLED=false#MCLOUD_ENABLED=true#g" reporting/configuration/reporting-service/variables.env
      sed -i "s#MCLOUD_URL=#MCLOUD_URL=$ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/mcloud/wd/hub#g" reporting/configuration/reporting-service/variables.env
      #TODO: generate secure htpasswd for mcloud
      sed -i "s#MCLOUD_USER=#MCLOUD_USER=demo#g" reporting/configuration/reporting-service/variables.env
      sed -i "s#MCLOUD_PASSWORD=#MCLOUD_PASSWORD=demo#g" reporting/configuration/reporting-service/variables.env
    fi

    if [[ $ZBR_SELENOID_ENABLED -eq 1 && $ZBR_REPORTING_ENABLED -eq 1 ]]; then
      # update reporting-jenkins integration vars
      sed -i "s#SELENIUM_ENABLED=false#SELENIUM_ENABLED=true#g" reporting/configuration/reporting-service/variables.env
      sed -i "s#SELENIUM_URL=#SELENIUM_URL=$ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/selenoid/wd/hub#g" reporting/configuration/reporting-service/variables.env
      #TODO: generate secure htpasswd for selenoid
      sed -i "s#SELENIUM_USER=#SELENIUM_USER=demo#g" reporting/configuration/reporting-service/variables.env
      sed -i "s#SELENIUM_PASSWORD=#SELENIUM_PASSWORD=demo#g" reporting/configuration/reporting-service/variables.env
    fi

    # finish with NGiNX default tool selection
    if [[ $ZBR_REPORTING_ENABLED -eq 1 ]]; then
      sed -i 's/default-proxy-server/zebrunner-proxy:80/g' ./nginx/conf.d/default.conf
      sed -i 's/default-proxy-host/zebrunner-proxy/g' ./nginx/conf.d/default.conf
    elif [[ $ZBR_MCLOUD_ENABLED -eq 1 ]]; then
      sed -i 's/default-proxy-server/stf-proxy:80/g' ./nginx/conf.d/default.conf
      sed -i 's/default-proxy-host/stf-proxy/g' ./nginx/conf.d/default.conf
    elif [[ $ZBR_JENKINS_ENABLED -eq 1 ]]; then
      sed -i 's|set $upstream_default default-proxy-server;||g' ./nginx/conf.d/default.conf
      sed -i 's|proxy_set_header Host default-proxy-host;||g' ./nginx/conf.d/default.conf
      sed -i 's|proxy_pass http://$upstream_default;|rewrite / /jenkins;|g' ./nginx/conf.d/default.conf
    elif [[ $ZBR_SONARQUBE_ENABLED -eq 1 ]]; then
      sed -i 's|set $upstream_default default-proxy-server;||g' ./nginx/conf.d/default.conf
      sed -i 's|proxy_set_header Host default-proxy-host;||g' ./nginx/conf.d/default.conf
      sed -i 's|proxy_pass http://$upstream_default;|rewrite / /sonarqube;|g' ./nginx/conf.d/default.conf
    else
      sed -i 's|proxy_pass http://$upstream_default;|root   /usr/share/nginx/html;|g' ./nginx/conf.d/default.conf
    fi

    # export all ZBR* variables to save user input
    export_settings

    echo
    echo_warning "Copy and save auto-generated crendentials. Detailes can be found also in NOTICE.txt"
    echo

    notice=NOTICE.txt
    echo "NOTICES AND INFORMATION" > $notice
    echo >> $notice
    echo >> $notice

    echo "ZEBRUNNER URL: $ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT" | tee -a $notice
    echo | tee -a $notice

    if [[ $ZBR_REPORTING_ENABLED -eq 1 ]]; then
      echo "REPORTING SERVICE CREDENTIALS:" | tee -a $notice
      echo "USER: admin/changeit" | tee -a $notice
      echo "IAM POSTGRES: postgres/$ZBR_IAM_POSTGRES_PASSWORD" | tee -a $notice
      echo "REPORTING POSTGRES: postgres/$ZBR_POSTGRES_PASSWORD" | tee -a $notice
      echo "RABBITMQ: $ZBR_RABBITMQ_USER/$ZBR_RABBITMQ_PASSWORD" | tee -a $notice
      echo "REDIS: $ZBR_REDIS_PASSWORD" | tee -a $notice
      echo | tee -a $notice

      if [[ ZBR_SMTP_ENABLED -eq 1 ]]; then
        echo "REPORTING SMTP INTEGRATIONS:" | tee -a $notice
        echo "SMTP HOST: $ZBR_SMTP_HOST:$ZBR_SMTP_PORT" | tee -a $notice
        echo "EMAIL: $ZBR_SMTP_EMAIL" | tee -a $notice
        echo "USER: $ZBR_SMTP_USER/$ZBR_SMTP_PASSWORD" | tee -a $notice
        echo | tee -a $notice
      fi
      if [[ ZBR_GITHUB_ENABLED -eq 1 ]]; then
        echo "REPORTING GITHUB INTEGRATIONS:" | tee -a $notice
        echo "GIT HOST: ${ZBR_GITHUB_HOST}" | tee -a $notice
        echo "CLIENT ID/SECRET: $ZBR_GITHUB_CLIENT_ID/$ZBR_GITHUB_CLIENT_SECRET" | tee -a $notice
        echo | tee -a $notice
      fi
    fi

    if [[ $ZBR_JENKINS_ENABLED -eq 1 ]]; then
      echo "JENKINS URL: $ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/jenkins" | tee -a $notice
      echo "JENKINS USER: admin/changeit" | tee -a $notice
      echo | tee -a $notice
    fi

    if [[ $ZBR_SONARQUBE_ENABLED -eq 1 ]]; then
      echo "SONARQUBE URL: $ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/sonarqube" | tee -a $notice
      echo "SONARQUBE USER: admin/admin" | tee -a $notice
      echo | tee -a $notice
    fi

    if [[ $ZBR_SELENOID_ENABLED -eq 1 ]]; then
      echo "SELENIUM HUB URL: $ZBR_PROTOCOL://demo:demo@$ZBR_HOSTNAME:$ZBR_PORT/selenoid/wd/hub" | tee -a $notice
      echo | tee -a $notice
    fi

    if [[ $ZBR_MCLOUD_ENABLED -eq 1 ]]; then
      echo "STF URL: $ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT/stf" | tee -a $notice
      echo "APPIUM HUB URL: $ZBR_PROTOCOL://demo:demo@$ZBR_HOSTNAME:$ZBR_PORT/mcloud/wd/hub" | tee -a $notice
      echo | tee -a $notice
    fi

    # append copyright and licensing info
    echo >> $notice
    echo "Copyright 2018-2021 ZEBRUNNER" >> $notice
    echo >> $notice

    echo "Licensed under the Apache License, Version 2.0 (the \"License\");" >> $notice
    echo "you may not use this file except in compliance with the License." >> $notice
    echo "You may obtain a copy of the License at" >> $notice
    echo >> $notice

    echo "http://www.apache.org/licenses/LICENSE-2.0" >> $notice
    echo >> $notice

    echo "Unless required by applicable law or agreed to in writing, software" >> $notice
    echo "distributed under the License is distributed on an \"AS IS\" BASIS," >> $notice
    echo "WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied." >> $notice
    echo "See the License for the specific language governing permissions and" >> $notice
    echo "limitations under the License." >> $notice

    echo_warning "Your services needs to be started after setup."
    confirm "" "      Start now?" "y"
    export start_services=$?
    echo
    echo

    if [[ $ZBR_SELENOID_ENABLED -eq 1 ]]; then
       selenoid/zebrunner.sh setup
    fi

    if [[ $start_services -eq 1 ]]; then
      start
    fi

  }

  shutdown() {
    if [ ! -f backup/settings.env ]; then
      echo_warning "You have to setup services in advance using: ./zebrunner.sh setup"
      echo_telegram
      exit -1
    fi

    echo_warning "Shutdown will erase all settings and data for \"${BASEDIR}\"!"
    confirm "" "      Do you want to continue?" "n"
    if [[ $? -eq 0 ]]; then
      exit
    fi

    print_banner

    rm -f nginx/conf.d/default.conf
    rm -f backup/settings.env

    rm -f reporting/database/reporting/sql/db-jenkins-integration.sql
    rm -f reporting/database/reporting/sql/db-mcloud-integration.sql
    rm -f reporting/database/reporting/sql/db-selenium-integration.sql

    jenkins/zebrunner.sh shutdown
    reporting/zebrunner.sh shutdown
    sonarqube/zebrunner.sh shutdown
    mcloud/zebrunner.sh shutdown
    selenoid/zebrunner.sh shutdown
    docker-compose down -v

  }

  start() {
    if [ ! -f backup/settings.env ]; then
      echo_warning "You have to setup services in advance using: ./zebrunner.sh setup"
      echo_telegram
      exit -1
    fi

    source backup/settings.env
    if [[ -z ${ZBR_VERSION} ]]; then
      ZBR_VERSION=1.0
    fi
    ACTUAL_VERSION=${ZBR_VERSION}

    source .env
    DESIRED_VERSION=${ZBR_VERSION}

    if [[ "${ACTUAL_VERSION}" < "${DESIRED_VERSION}" ]]; then
      echo_warning "You have to upgrade services in advance using: ./zebrunner.sh upgrade"
      echo_telegram
      exit -1
    fi

    print_banner

    # create infra network only if not exist
    docker network inspect infra >/dev/null 2>&1 || docker network create infra

    #-------------- START EVERYTHING ------------------------------
    selenoid/zebrunner.sh start
    mcloud/zebrunner.sh start
    jenkins/zebrunner.sh start
    reporting/zebrunner.sh start
    sonarqube/zebrunner.sh start

    docker-compose up -d
  }

  stop() {
    if [ ! -f backup/settings.env ]; then
      echo_warning "You have to setup services in advance using: ./zebrunner.sh setup"
      echo_telegram
      exit -1
    fi

    jenkins/zebrunner.sh stop
    reporting/zebrunner.sh stop
    sonarqube/zebrunner.sh stop
    mcloud/zebrunner.sh stop
    selenoid/zebrunner.sh stop
    docker-compose stop
  }

  restart() {
    if [ ! -f backup/settings.env ]; then
      echo_warning "You have to setup services in advance using: ./zebrunner.sh setup"
      echo_telegram
      exit -1
    fi

    down
    start
  }

  down() {
    if [ ! -f backup/settings.env ]; then
      echo_warning "You have to setup services in advance using: ./zebrunner.sh setup"
      echo_telegram
      exit -1
    fi

    jenkins/zebrunner.sh down
    reporting/zebrunner.sh down
    sonarqube/zebrunner.sh down
    mcloud/zebrunner.sh down
    selenoid/zebrunner.sh down
    docker-compose down
  }

  backup() {
    if [ ! -f backup/settings.env ]; then
      echo_warning "You have to setup services in advance using: ./zebrunner.sh setup"
      echo_telegram
      exit -1
    fi

    confirm "" "      Your services will be stopped. Do you want to do a backup now?" "n"
    if [[ $? -eq 0 ]]; then
      exit
    fi

    print_banner

    stop

    cp ./nginx/conf.d/default.conf ./nginx/conf.d/default.conf.bak
    cp backup/settings.env backup/settings.env.bak
    if [[ -f reporting/database/reporting/sql/db-jenkins-integration.sql ]]; then
      cp reporting/database/reporting/sql/db-jenkins-integration.sql reporting/database/reporting/sql/db-jenkins-integration.sql.bak
    fi
    if [[ -f reporting/database/reporting/sql/db-mcloud-integration.sql ]]; then
      cp reporting/database/reporting/sql/db-mcloud-integration.sql reporting/database/reporting/sql/db-mcloud-integration.sql.bak
    fi
    if [[ -f reporting/database/reporting/sql/db-selenium-integration.sql ]]; then
      cp reporting/database/reporting/sql/db-selenium-integration.sql reporting/database/reporting/sql/db-selenium-integration.sql.bak
    fi


    jenkins/zebrunner.sh backup
    reporting/zebrunner.sh backup
    sonarqube/zebrunner.sh backup
    mcloud/zebrunner.sh backup
    selenoid/zebrunner.sh backup

    echo_warning "Your services needs to be started after backup."
    confirm "" "      Start now?" "y"
    if [[ $? -eq 1 ]]; then
      start
    fi

  }

  restore() {
    if [ ! -f backup/settings.env ]; then
      echo_warning "You have to setup services in advance using: ./zebrunner.sh setup"
      echo_telegram
      exit -1
    fi

    confirm "" "      Your services will be stopped and current data might be lost. Do you want to do a restore now?" "n"
    if [[ $? -eq 0 ]]; then
      exit
    fi

    print_banner

    stop
    cp ./nginx/conf.d/default.conf.bak ./nginx/conf.d/default.conf
    cp backup/settings.env.bak backup/settings.env
    if [[ -f reporting/database/reporting/sql/db-jenkins-integration.sql.bak ]]; then
      cp reporting/database/reporting/sql/db-jenkins-integration.sql.bak reporting/database/reporting/sql/db-jenkins-integration.sql
    fi
    if [[ -f reporting/database/reporting/sql/db-mcloud-integration.sql.bak ]]; then
      cp reporting/database/reporting/sql/db-mcloud-integration.sql.bak reporting/database/reporting/sql/db-mcloud-integration.sql
    fi
    if [[ -f reporting/database/reporting/sql/db-selenium-integration.sql.bak ]]; then
      cp reporting/database/reporting/sql/db-selenium-integration.sql.bak reporting/database/reporting/sql/db-selenium-integration.sql
    fi

    jenkins/zebrunner.sh restore
    reporting/zebrunner.sh restore
    sonarqube/zebrunner.sh restore
    mcloud/zebrunner.sh restore
    selenoid/zebrunner.sh restore
    down

    echo_warning "Your services needs to be started after restore."
    confirm "" "      Start now?" "y"
    if [[ $? -eq 1 ]]; then
      start
    fi

  }

  upgrade() {
    if [ ! -f backup/settings.env ]; then
      echo_warning "You have to setup services in advance using: ./zebrunner.sh setup"
      echo_telegram
      exit -1
    fi

    confirm "" "      Do you want to do an upgrade?" "n"
    if [[ $? -eq 0 ]]; then
      exit
    fi

    patch/1.1.sh
    p1_1=$?
    if [[ ${p1_1} -eq 1 ]]; then
      echo "ERROR! 1.1 patchset was not applied correctly!"
      exit -1
    fi

    patch/1.2.sh
    p1_2=$?
    if [[ ${p1_2} -eq 1 ]]; then
      echo "ERROR! 1.2 patchset was not applied correctly!"
      exit -1
    fi

    patch/1.3.sh
    p1_3=$?
    if [[ ${p1_3} -eq 1 ]]; then
      echo "ERROR! 1.3 patchset was not applied correctly!"
      exit -1
    fi

    patch/1.4.sh
    p1_4=$?
    if [[ ${p1_4} -eq 1 ]]; then
      echo "ERROR! 1.4 patchset was not applied correctly!"
      exit -1
    fi

    patch/1.5.sh
    p1_5=$?
    if [[ ${p1_5} -eq 1 ]]; then
      echo "ERROR! 1.5 patchset was not applied correctly!"
      exit -1
    fi

    patch/1.6.sh
    p1_6=$?
    if [[ ${p1_6} -eq 1 ]]; then
      echo "ERROR! 1.6 patchset was not applied correctly!"
      exit -1
    fi

    patch/1.7.sh
    p1_7=$?
    if [[ ${p1_7} -eq 1 ]]; then
      echo "ERROR! 1.7 patchset was not applied correctly!"
      exit -1
    fi

    # IMPORTANT! Increment latest verification to new version, i.e. p1_3, p1_4 etc to verify latest upgrade status
    if [[ ${p1_7} -eq 2 ]]; then
      echo "No need to restart service as nothing was upgraded."
      exit -1
    fi

    echo_warning "Your services needs to restart to finish important updates."
    confirm "" "      Restart now?" "y"
    if [[ $? -eq 1 ]]; then
      down
      start
    fi

  }

  version() {
    if [ ! -f backup/settings.env ]; then
      echo_warning "You have to setup services in advance using: ./zebrunner.sh setup"
      echo_telegram
      exit -1
    fi

    source backup/settings.env

    echo "
      zebrunner: ${ZBR_VERSION}
      $(jenkins/zebrunner.sh version)
      $(mcloud/zebrunner.sh version)
      $(reporting/zebrunner.sh version)
      $(selenoid/zebrunner.sh version)
      $(sonarqube/zebrunner.sh version)"
  }

  enableLayer() {
    local layer=$1
    local message=$2
    local isEnabled=$3

    echo
    confirm "$message" "Enable?" "$isEnabled"
    if [[ $? -eq 1 ]]; then
      # enable component/layer
      if [[ -f $layer/.disabled ]]; then
        rm $layer/.disabled
      fi
      return 1
    else
      disableLayer $layer
      return 0
    fi
  }

  disableLayer() {
    # disbale component/layer
    echo > $1/.disabled
    return 0
  }

  set_global_settings() {
    # Setup global settings: protocol, hostname and port
    echo "Zebrunner General Settings"
    local is_confirmed=0
    if [[ -z $ZBR_HOSTNAME ]]; then
      ZBR_HOSTNAME=$HOSTNAME
    fi

    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Protocol [$ZBR_PROTOCOL]: " local_protocol
      if [[ ! -z $local_protocol ]]; then
        ZBR_PROTOCOL=$local_protocol
      fi

      read -p "Fully qualified domain name (ip) [$ZBR_HOSTNAME]: " local_hostname
      if [[ ! -z $local_hostname ]]; then
        ZBR_HOSTNAME=$local_hostname
      fi

      read -p "Port [$ZBR_PORT]: " local_port
      if [[ ! -z $local_port ]]; then
        ZBR_PORT=$local_port
      fi

      confirm "Zebrunner URL: $ZBR_PROTOCOL://$ZBR_HOSTNAME:$ZBR_PORT" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_PROTOCOL=$ZBR_PROTOCOL
    export ZBR_HOSTNAME=$ZBR_HOSTNAME
    export ZBR_PORT=$ZBR_PORT

  }

  set_reporting_settings() {
    # Collect reporting settings
    ## Crypto token and salt
    if [[ -z $ZBR_TOKEN_SIGNING_SECRET ]]; then
      # generate random value as it is first setup
      ZBR_TOKEN_SIGNING_SECRET=`random_string`
    fi
    if [[ -z $ZBR_CRYPTO_SALT ]]; then
      # generate random value as it is first setup
      ZBR_CRYPTO_SALT=`random_string`
    fi
    export ZBR_TOKEN_SIGNING_SECRET=$ZBR_TOKEN_SIGNING_SECRET
    export ZBR_CRYPTO_SALT=$ZBR_CRYPTO_SALT

    ## iam-service posgtres
    if [[ -z $ZBR_IAM_POSTGRES_PASSWORD ]]; then
      # generate random value as it is first setup
      ZBR_IAM_POSTGRES_PASSWORD=`random_string`
    fi
    export ZBR_IAM_POSTGRES_PASSWORD=$ZBR_IAM_POSTGRES_PASSWORD

    ## reporting posgtres instance
    if [[ -z $ZBR_POSTGRES_PASSWORD ]]; then
      # generate random value as it is first setup
      ZBR_POSTGRES_PASSWORD=`random_string`
    fi
    export ZBR_POSTGRES_PASSWORD=$ZBR_POSTGRES_PASSWORD


    echo
    confirm "Use AWS S3 bucket for storing test artifacts (logs, video, screenshots etc)? Embedded Minio Storage can be configured if you don't have Amazon account." "Use?" "$ZBR_AWS_S3_ENABLED"
    if [[ $? -eq 1 ]]; then
      ZBR_AWS_S3_ENABLED=1
      ZBR_MINIO_ENABLED=0
      set_aws_storage_settings
    else
      ZBR_MINIO_ENABLED=1
    fi

    ## email-service (smtp)
    echo
    confirm "Use SMTP for emailing test results?" "Use?" "$ZBR_SMTP_ENABLED"
    if [[ $? -eq 0 ]]; then
      ZBR_SMTP_ENABLED=0
    else
      ZBR_SMTP_ENABLED=1
      local is_confirmed=0
      while [[ $is_confirmed -eq 0 ]]; do
        read -p "Host [$ZBR_SMTP_HOST]: " local_smtp_host
        if [[ ! -z $local_smtp_host ]]; then
          ZBR_SMTP_HOST=$local_smtp_host
        fi

        read -p "Port [$ZBR_SMTP_PORT]: " local_smtp_port
        if [[ ! -z $local_smtp_port ]]; then
          ZBR_SMTP_PORT=$local_smtp_port
        fi

        read -p "Sender email [$ZBR_SMTP_EMAIL]: " local_smtp_email
        if [[ ! -z $local_smtp_email ]]; then
          ZBR_SMTP_EMAIL=$local_smtp_email
        fi

        read -p "User [$ZBR_SMTP_USER]: " local_smtp_user
        if [[ ! -z $local_smtp_user ]]; then
          ZBR_SMTP_USER=$local_smtp_user
        fi

        read -p "Password [$ZBR_SMTP_PASSWORD]: " local_smtp_password
        if [[ ! -z $local_smtp_password ]]; then
          ZBR_SMTP_PASSWORD=$local_smtp_password
        fi

        echo
        echo "SMTP Integration"
        echo "host=$ZBR_SMTP_HOST:$ZBR_SMTP_PORT"
        echo "email=$ZBR_SMTP_EMAIL"
        echo "user=$ZBR_SMTP_USER"
        echo "password=$ZBR_SMTP_PASSWORD"
        confirm "" "Continue?" "y"
        is_confirmed=$?
      done
    fi

    export ZBR_SMTP_HOST=$ZBR_SMTP_HOST
    export ZBR_SMTP_PORT=$ZBR_SMTP_PORT
    export ZBR_SMTP_EMAIL=$ZBR_SMTP_EMAIL
    export ZBR_SMTP_USER=$ZBR_SMTP_USER
    export ZBR_SMTP_PASSWORD=$ZBR_SMTP_PASSWORD


    ## reporting rabbitmq
    if [[ -z $ZBR_RABBITMQ_PASSWORD ]]; then
      # generate random value as it is first setup
      ZBR_RABBITMQ_PASSWORD=`random_string`
    fi
    export ZBR_RABBITMQ_USER=$ZBR_RABBITMQ_USER
    export ZBR_RABBITMQ_PASSWORD=$ZBR_RABBITMQ_PASSWORD

    ## reporting redis
    if [[ -z $ZBR_REDIS_PASSWORD ]]; then
      # generate random value as it is first setup
      ZBR_REDIS_PASSWORD=`random_string`
    fi
    export ZBR_REDIS_PASSWORD=$ZBR_REDIS_PASSWORD

    ## test launchers git integration
    echo
    confirm "Use GitHub integration for Test Launchers in Reporting UI?" "Use?" "$ZBR_GITHUB_ENABLED"
    if [[ $? -eq 0 ]]; then
      ZBR_GITHUB_ENABLED=0
    else
      ZBR_GITHUB_ENABLED=1
      local is_confirmed=0
      while [[ $is_confirmed -eq 0 ]]; do
        read -p "Git host [$ZBR_GITHUB_HOST]: " local_git
        if [[ ! -z $local_git ]]; then
          ZBR_GITHUB_HOST=$local_git
        fi

        read -p "Client ID [$ZBR_GITHUB_CLIENT_ID]: " local_client_id
        if [[ ! -z $local_client_id ]]; then
          ZBR_GITHUB_CLIENT_ID=$local_client_id
        fi

        read -p "Client Secret [$ZBR_GITHUB_CLIENT_SECRET]: " local_secret_id
        if [[ ! -z $local_secret_id ]]; then
          ZBR_GITHUB_CLIENT_SECRET=$local_secret_id
        fi

        echo
        echo "GIT Integration"
        echo "Host: ${ZBR_GITHUB_HOST}"
        echo "Client ID: ${ZBR_GITHUB_CLIENT_ID}"
        echo "Client Secret: ${ZBR_GITHUB_CLIENT_SECRET}"
        confirm "" "Continue?" "y"
        is_confirmed=$?
      done
    fi

    export ZBR_GITHUB_HOST=$ZBR_GITHUB_HOST
    export ZBR_GITHUB_CLIENT_ID=$ZBR_GITHUB_CLIENT_ID
    export ZBR_GITHUB_CLIENT_SECRET=$ZBR_GITHUB_CLIENT_SECRET

  }

  # https://github.com/zebrunner/zebrunner/issues/384 investigate possibility to make sub-components configurable independently
  # https://github.com/zebrunner/selenoid/issues/16 investigate possibility to make selenoid auto-configurable
  # IMPORTANT! copy of this method exists in selenoid/zebrunner.sh and maybe will be added to reporting/zebrunner.sh
  set_aws_storage_settings() {
    ## AWS S3 storage
    local is_confirmed=0
    #TODO: provide a link to documentation howto create valid S3 bucket
    echo
    echo "AWS S3 storage"
    while [[ $is_confirmed -eq 0 ]]; do
      read -p "Region [$ZBR_STORAGE_REGION]: " local_region
      if [[ ! -z $local_region ]]; then
        ZBR_STORAGE_REGION=$local_region
      fi

      ZBR_STORAGE_ENDPOINT_PROTOCOL="https"
      ZBR_STORAGE_ENDPOINT_HOST="s3.${ZBR_STORAGE_REGION}.amazonaws.com:443"

      read -p "Bucket [$ZBR_STORAGE_BUCKET]: " local_bucket
      if [[ ! -z $local_bucket ]]; then
        ZBR_STORAGE_BUCKET=$local_bucket
      fi

      read -p "Access key [$ZBR_STORAGE_ACCESS_KEY]: " local_access_key
      if [[ ! -z $local_access_key ]]; then
        ZBR_STORAGE_ACCESS_KEY=$local_access_key
      fi

      read -p "Secret key [$ZBR_STORAGE_SECRET_KEY]: " local_secret_key
      if [[ ! -z $local_secret_key ]]; then
        ZBR_STORAGE_SECRET_KEY=$local_secret_key
      fi

      if [[ $ZBR_REPORTING_ENABLED -eq 0 ]]; then
        export ZBR_MINIO_ENABLED=0
        read -p "[Optional] Tenant [$ZBR_STORAGE_TENANT]: " local_value
        if [[ ! -z $local_value ]]; then
          ZBR_STORAGE_TENANT=$local_value
        fi
      else
        read -p "UserAgent key [$ZBR_STORAGE_AGENT_KEY]: " local_agent_key
        if [[ ! -z $local_agent_key ]]; then
          ZBR_STORAGE_AGENT_KEY=$local_agent_key
        fi
      fi

      echo "Region: $ZBR_STORAGE_REGION"
      echo "Endpoint: $ZBR_STORAGE_ENDPOINT_PROTOCOL://$ZBR_STORAGE_ENDPOINT_HOST"
      echo "Bucket: $ZBR_STORAGE_BUCKET"
      echo "Access key: $ZBR_STORAGE_ACCESS_KEY"
      echo "Secret key: $ZBR_STORAGE_SECRET_KEY"
      echo "Agent key: $ZBR_STORAGE_AGENT_KEY"
      echo "Tenant: $ZBR_STORAGE_TENANT"
      confirm "" "Continue?" "y"
      is_confirmed=$?
    done

    export ZBR_STORAGE_REGION=$ZBR_STORAGE_REGION
    export ZBR_STORAGE_ENDPOINT_PROTOCOL=$ZBR_STORAGE_ENDPOINT_PROTOCOL
    export ZBR_STORAGE_ENDPOINT_HOST=$ZBR_STORAGE_ENDPOINT_HOST
    export ZBR_STORAGE_BUCKET=$ZBR_STORAGE_BUCKET
    export ZBR_STORAGE_ACCESS_KEY=$ZBR_STORAGE_ACCESS_KEY
    export ZBR_STORAGE_SECRET_KEY=$ZBR_STORAGE_SECRET_KEY
    export ZBR_STORAGE_AGENT_KEY=$ZBR_STORAGE_AGENT_KEY
  }

  export_settings() {
    export -p | grep "ZBR" > backup/settings.env
  }

  random_string() {
    cat /dev/urandom | env LC_CTYPE=C tr -dc a-zA-Z0-9 | head -c 48; echo
  }

  confirm() {
    local message=$1
    local question=$2
    local isEnabled=$3

    if [[ "$isEnabled" == "1" ]]; then
      isEnabled="y"
    fi
    if [[ "$isEnabled" == "0" ]]; then
      isEnabled="n"
    fi

    while true; do
      if [[ ! -z $message ]]; then
        echo "$message"
      fi

      read -p "$question y/n [$isEnabled]:" response
      if [[ -z $response ]]; then
        if [[ "$isEnabled" == "y" ]]; then
          return 1
        fi
        if [[ "$isEnabled" == "n" ]]; then
          return 0
        fi
      fi

      if [[ "$response" == "y" || "$response" == "Y" ]]; then
        return 1
      fi

      if [[ "$response" == "n" ||  "$response" == "N" ]]; then
        return 0
      fi

      echo "Please answer y (yes) or n (no)."
      echo
    done
  }

  echo_warning() {
    echo "
      WARNING! $1"
  }

  echo_telegram() {
    echo "
      For more help join telegram channel: https://t.me/zebrunner
      "
  }

  echo_help() {
    echo "
      Usage: ./zebrunner.sh [option]
      Flags:
          --help | -h    Print help
      Arguments:
          setup          Setup Zebrunner Community Edition
      	  start          Start container
      	  stop           Stop and keep container
      	  restart        Restart container
      	  down           Stop and remove container
      	  shutdown       Stop and remove container, clear volumes
      	  backup         Backup container
      	  restore        Restore container
          upgrade        Upgrade to the latest version of Zebrunner Community Edition
      	  version        Version of components"
      echo_telegram
      exit 0
  }

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd ${BASEDIR}

case "$1" in
    setup)
        setup
        ;;
    start)
	start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    down)
        down
        ;;
    shutdown)
        shutdown
        ;;
    backup)
        backup
        ;;
    restore)
        restore
        ;;
    upgrade)
        upgrade
        ;;
    version)
        version
        ;;
    *)
        echo "Invalid option detected: $1"
        echo_help
        exit 1
        ;;
esac

