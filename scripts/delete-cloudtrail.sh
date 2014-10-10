#!/bin/bash
set -e

# Supported regions
allregions="us-east-1 us-west-1 us-west-2 eu-west-1 sa-east-1 ap-northeast-1 ap-southeast-1 ap-southeast-2"

help(){
    echo "delete-cloudtrail [-a <accountname>] -b <bucket> -c <config> -r region -n"
    echo ""
    echo " -a <accountname>: optional. Used as suffix for SNS topic and trail name"
    echo " -c <config>: configuration file to contain AWS key/secret"
    echo " -n         : Dryrun. Print out the commands"
    echo " -h         : Help"
}

dryrun=0
while getopts "a:b:c:r:hn" OPTION
do
    case $OPTION in
        a)
          accountname=$OPTARG
          ;;
        c)
          config=$OPTARG
          ;;
        n)
          dryrun=1
          ;;
        [h?])
          help
          exit
          ;;
    esac
done

if [ -z $config ]; then
    help
    exit 1
fi

if [ ! -f $config ]; then
    echo "$config doesn't exist."
    exit 1
fi

if [ -z "$accountname" ]; then
    answer='N'
    accountname=$(aws iam get-user --query User.UserName| sed 's/\"//g')
    echo -n "Do you accept the default name: $accountname? [Y/N]"
    read answer
    echo ""
    if [ "X$answer" != "XY" ]; then
        echo "Do nothing. Quit."
        exit 0
    fi
fi

# Don't exist on non-zero code because the following aws commmands exit code
# is '1' on sucess.
set +e 
# Cloudtrail name
trailname=${accountname}-cloudtrail

# Delete SNS topics
for i in $allregions
do 
    snstopic=${trailname}-$i
    topicarn=$(aws sns list-topics --region $i |grep $snstopic | awk '{print $2}' | sed 's/\"//g')
    if [ $dryrun -eq 1 ]; then
        echo "aws sns delete-topic --topic-arn $topicarn --region $i"
    else
        aws sns delete-topic --topic-arn $topicarn --region $i
    fi
done

# Delete Cloudtrails
for i in $allregions
do 
    snstopic=${trailname}-$i
    echo "aws cloudtrail delete-trail --region $i --name $trailname"
    if [ $dryrun -eq 0 ]; then
        aws cloudtrail delete-trail --region $i --name $trailname
    fi
done
[ $dryrun -eq 1 ] && echo "Dryrun only. Nothing changed." 

# Delete sqs?
answer='N'
queuename=${accountname}-cloudtrail
if aws sqs get-queue-url --queue-name $queuename > /dev/null 2>&1; then
    echo -n "Do you want to delete SQS $queuename? [Y/N]"
    read answer
    echo ""
    if [ "X$answer" != "XY" ]; then
        echo "Do nothing. Quit."
        exit 0
    else
        queueurl=$(aws sqs get-queue-url --queue-name idg-aws-dev-cloudtrail --query QueueUrl | sed 's/\"//g')
        if [ $dryrun -eq 0 ]; then
            aws sqs delete-queue --queue-url $queueurl
        else
            echo "aws sqs delete --queue-url $queueurl"
            echo "Dryrun mode. Nothing is changed."
        fi
    fi
fi
