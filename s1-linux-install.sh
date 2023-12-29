#!/bin/bash
##############################################################################################################
# Description:  Bash script to aid with automating S1 Agent install on Linux
# 
# Usage:    sudo ./s1-agent-helper.sh S1_CONSOLE_PREFIX API_KEY SITE_TOKEN VERSION_STATUS
# 
# Version:  1.0
##############################################################################################################


S1_REPOSITORY_USERNAME=$1
S1_REPOSITORY_PASSWORD=$2
S1_SITE_TOKEN=$3
S1_AGENT_VERSION=$4  

# Debugging ####################################################
# echo "user: $S1_REPOSITORY_USERNAME"
# echo "pass: $S1_REPOSITORY_PASSWORD"
# echo "token: $S1_SITE_TOKEN"
# echo "version: $S1_AGENT_VERSION"



Color_Off='\033[0m'       # Text Resets
# Regular Colors
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow

# Check if the minimum number of arguments have been passed
if [ $# -lt 4 ]; then
    printf "\n${Red}ERROR:  Expecting at least 4 arguments to be passed. \n${Color_Off}"
    printf "Example usage: \n"
    printf "ie:${Green} sudo $0 \$S1_REPOSITORY_USERNAME \$S1_REPOSITORY_PASSWORD \$S1_SITE_TOKEN 23.3.2.12  \n${Color_Off}"
    printf "\nFor instructions on obtaining a ${Purple}Site Token${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
    printf "    ${Blue}https://community.sentinelone.com/s/article/000004904 ${Color_Off} \n\n"
    printf "\nFor instructions on obtaining ${Purple}Repository Credentials${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
    printf "    ${Blue}https://community.sentinelone.com/s/article/000008771 ${Color_Off} \n\n"
    exit 1
fi

# Check if running as root
function check_root () {
    if [[ $(/usr/bin/id -u) -ne 0 ]]; then
        printf "\n${Red}ERROR:  This script must be run as root.  Please retry with 'sudo'.${Color_Off}\n"
        exit 1;
    fi
}


function check_args () {
        # Check if the value of S1_SITE_TOKEN is in the right format
    if ! echo $S1_SITE_TOKEN | base64 -d | grep sentinelone.net &> /dev/null ; then
        printf "\n${Red}ERROR:  Site Token does not decode correctly.  Please ensure that you've passed a valid Site Token as the first argument to the script. \n${Color_Off}"
        printf "\nFor instructions on obtaining a ${Purple}Site Token${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
        printf "    ${Blue}https://community.sentinelone.com/s/article/000004904 ${Color_Off} \n\n"
        exit 1
    fi

    # Check if the value of S1_REPOSITORY_USERNAME is in the right format
    if ! echo $S1_REPOSITORY_USERNAME | base64 -d | grep -E '^[0-9]+\:(aws|gcp)\:[a-zA-Z0-9-]+\:[0-9]{18,19}$' &> /dev/null ; then
        printf "\n${Red}ERROR:  That value passed for S1_REPOSITORY_USERNAME does not decode correctly.  Please ensure that you've passed a valid Registry Username as the second argument to the script. \n${Color_Off}"
        printf "\nFor instructions on obtaining ${Purple}Registry Credentials${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
        printf "    ${Blue}https://community.sentinelone.com/s/article/000008771 ${Color_Off} \n\n"
        exit 1
    fi

    # Check if the value of S1_REPOSITORY_PASSWORD is in the right format
    if ! [ ${#S1_REPOSITORY_PASSWORD} -gt 160 ]; then
        printf "\n${Red}ERROR:  That value passed for S1_REPOSITORY_PASSWORD did not pass a basic length test (longer than 160 characters).  Please ensure that you've passed a valid Registry Password as the second argument to the script. \n${Color_Off}"
        printf "\nFor instructions on obtaining ${Purple}Registry Credentials${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
        printf "    ${Blue}https://community.sentinelone.com/s/article/000008771 ${Color_Off} \n\n"
        exit 1
    fi

    # Check if the value of S1_AGENT_VERSION is in the right format
    if ! echo $S1_AGENT_VERSION | grep -E '^[0-9]{2}\.[0-9]\.[0-9]\.[0-9]+$' &> /dev/null ; then
        printf "\n${Red}ERROR:  The value passed for S1_AGENT_VERSION is not in the correct format.  Examples of valid values are:  23.3.2-ga and 23.4.1-ea \n\n${Color_Off}"
        exit 1
    fi

}


function find_agent_info_by_architecture () {
    OS_ARCH=$(uname -p)
    if [[ $OS_ARCH == "aarch64" ]]; then
        # for i in {0..20}; do
        #     FN=$(cat response.txt | jq -r ".data[$i].fileName")
        #     if [[ $FN == *$OS_ARCH* ]]; then
        #         AGENT_FILE_NAME=$(cat response.txt | jq -r ".data[$i].fileName")
        #         AGENT_DOWNLOAD_LINK=$(cat response.txt | jq -r ".data[$i].link")
        #         break
        #     fi
        # done
        echo "aarch64"
    elif [[ $OS_ARCH == "x86_64" || $OS_ARCH == "unknown" ]]; then
        # for i in {0..20}; do
        #     FN=$(cat response.txt | jq -r ".data[$i].fileName")
        #     if [[ $FN != *"aarch"* ]]; then
        #         AGENT_FILE_NAME=$(cat response.txt | jq -r ".data[$i].fileName")
        #         AGENT_DOWNLOAD_LINK=$(cat response.txt | jq -r ".data[$i].link")
        #         break
        #     fi
        # done
        echo "x86_64"
    else
        printf "\n${Red}ERROR:  OS_ARCH is neither 'aarch64' nor 'x86_64':  $OS_ARCH ${Color_Off}\n"
    fi
}


# Detect if the Linux Platform uses RPM/DEB packages and the correct Package Manager to use
function detect_pkg_mgr_info () {
    if (cat /etc/*release |grep 'ID=ubuntu' || cat /etc/*release |grep 'ID=debian'); then
        #FILE_EXTENSION='.deb'
        PACKAGE_MANAGER='apt'
       # AGENT_INSTALL_SYNTAX='dpkg -i'
       install_using_apt
    elif (cat /etc/*release |grep 'ID="rhel"' || cat /etc/*release |grep 'ID="amzn"' || cat /etc/*release |grep 'ID="centos"' || cat /etc/*release |grep 'ID="ol"' || cat /etc/*release |grep 'ID="scientific"' || cat /etc/*release |grep 'ID="rocky"' || cat /etc/*release |grep 'ID="almalinux"'); then
      #  FILE_EXTENSION='.rpm'
        PACKAGE_MANAGER='yum'
      #  AGENT_INSTALL_SYNTAX='rpm -i --nodigest'
      install_using_yum
    elif (cat /etc/*release |grep 'ID="sles"'); then
      #  FILE_EXTENSION='.rpm'
        PACKAGE_MANAGER='zypper'
      #  AGENT_INSTALL_SYNTAX='rpm -i --nodigest'
      install_using_yum
    elif (cat /etc/*release |grep 'ID="fedora"' || cat /etc/*release |grep 'ID=fedora'); then
      #  FILE_EXTENSION='.rpm'
        PACKAGE_MANAGER='dnf'
      #  AGENT_INSTALL_SYNTAX='rpm -i --nodigest'
      install_using_yum
    else
        printf "\n${Red}ERROR:  Unknown Release ID: $1 ${Color_Off}\n"
        cat /etc/*release
        echo ""
        exit 1
    fi
}


function install_using_apt () {
    echo "installing with apt..."
    S1_REPOSITORY_URL="deb.sentinelone.net"
    apt update
    apt install -y curl gnupg apt-transport-https
    # add public signature verification key for the repository to ensure the integrity and authenticity of packages
    curl -s https://us-apt.pkg.dev/doc/repo-signing-key.gpg | apt-key add - && curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    # remove any pre-existing s1-registry.list
    rm -f /etc/apt/sources.list.d/s1-registry.list
    # add the GA repository to the list of sources
    echo "deb [trusted=yes] https://${S1_REPOSITORY_USERNAME}:${S1_REPOSITORY_PASSWORD}@${S1_REPOSITORY_URL} apt-ga main" | tee -a /etc/apt/sources.list.d/s1-registry.list
    # add the EA repository to the list of sources (if the customer wants to use EA packages)
    echo "deb [trusted=yes] https://${S1_REPOSITORY_USERNAME}:${S1_REPOSITORY_PASSWORD}@${S1_REPOSITORY_URL} apt-ea main" | tee -a /etc/apt/sources.list.d/s1-registry.list
    cat /etc/apt/sources.list.d/s1-registry.list
    apt update
    apt install -y sentinelagent=${S1_AGENT_VERSION}
}


function install_using_yum () {
    echo "installing with yum..."
    S1_REPOSITORY_URL="rpm.sentinelone.net"

    yum -y update

    rpm --import https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
    
    # remove /etc/yum.repos.d/sentinel-registry-ga.repo if it exists already
    #rm -f /etc/yum.repos.d/sentinel-registry-ga.repo

#     echo -e "[yum-ga]\n\
# name=yum-ga\n\
# baseurl=https://${S1_REPOSITORY_URL}/yum-ga\n\
# enabled=1\n\
# repo_gpgcheck=0\n\
# gpgcheck=0\n\
# username=${S1_REPOSITORY_USERNAME}\n\
# password=${S1_REPOSITORY_PASSWORD}" > /etc/yum.repos.d/sentinel-registry-ga.repo \
    cat <<- EOF > /etc/yum.repos.d/sentinel-registry-ga.repo
[yum-ga]
name=yum-ga
baseurl=https://${S1_REPOSITORY_URL}/yum-ga
enabled=1
repo_gpgcheck=0
gpgcheck=0
username=${S1_REPOSITORY_USERNAME}
password=${S1_REPOSITORY_PASSWORD}"
EOF

    # remove /etc/yum.repos.d/sentinel-registry-ea.repo if it exists already
    rm -f /etc/yum.repos.d/sentinel-registry-ea.repo

    echo -e "[yum-ea]\n\
name=yum-ea\n\
baseurl=https://${S1_REPOSITORY_URL}/yum-ea\n\
enabled=1\n\
repo_gpgcheck=0\n\
gpgcheck=0\n\
username=${S1_REPOSITORY_USERNAME}\n\
password=${S1_REPOSITORY_PASSWORD}" > /etc/yum.repos.d/sentinel-registry-ea.repo

    yum makecache
    yum install -y SentinelAgent-${S1_AGENT_VERSION}-1.${OS_ARCH}
}

# dnf????

# zypper???


check_root
check_args

# need to test on ARM!!!
find_agent_info_by_architecture


detect_pkg_mgr_info


# printf "\n${Green}SUCCESS:  Finished installing SentinelOne Agent. ${Color_Off}\n\n"















# Set the Site Token
sentinelctl management token set $S1_SITE_TOKEN

# Start the Agent
sentinelctl control start



# TODO:
# - handle incorrect agent version number (ie: doesn't exist)
# - use heredoc syntax for legibility
# - 
# - 