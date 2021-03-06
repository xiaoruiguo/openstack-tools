#!/bin/bash
# 
#-accept as input 3 arguments: an hypervisor _or_ a vm ID, a REASON and a sender ("name surname").
#-extract the user_id mail address
#-prepare an email to be sent via sendmail to the user _and_ sysadmin@s3it.lists.uzh.ch with sysadmin as sender
#-the text should be something on the line:
#   "Dear Sciencecloud user,
#    this is a notification that your VM {name} with UUID {UUID} has crashed due to {REASON} and it is currently shutoff.
#    It can be restarted at any time.
#    Apologies for any inconvenience this may cause you.
#    If you have further question please write to help@s3it.uzh.ch
#    Best regards,
#    On behalf of the S3IT sysadmin,
#   {sender}
#
#-should warn about VMs started from a member of s3it and not belonging to our projects
#
set -e

USAGE="$0 HYPERVISOR|VM_ID REASON SENDER_EMAIL SENDER_NAME"
    
# check if a openstack username is set...
[ -z "$OS_USERNAME" ] && {
    echo "Error: No openstack username set."
    echo "Did you load your OpenStack credentials??"
    exit 42
}

[ 4 -ne $# ] && {
    echo "Error: Exactly 4 args are required" >&2
    echo $USAGE
    exit 1
}

ARG1=$(echo $1 | tr '[:upper:]' '[:lower:]')
echo $ARG1
#check if arg 1 is an hypervisor or an UUID
if [[ $ARG1 =~ ^node-[a-z][0-9][0-9]?-[0-9][0-9](-[0-9][0-9])?$ ]]; then
    HYPERVISOR=$ARG1
elif [[ $ARG1 =~ ^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$ ]]; then
    VM_ID=$ARG1
else
    echo "Error: Invalid argument: '$1'" >&2
    echo $USAGE
    exit 2
fi

#check if arg 2 is a valid REASON
#maybe not
REASON="an unknown reason"
[ -z "$2" ] || REASON="$2"

#sender argument is here in case you need to override the sender field of the message.
#check if arg 3 is a valid sender..
[[ "$3" =~ ^[a-z0-9.]+@.*uzh\.ch$ ]] || {
    echo "Error: Invalid sender email: '$3'" >&2
    echo $USAGE
    exit 3
}
SENDER_EMAIL="$3"

[[ "$4" =~ ^[A-Z][a-z]+\ [A-Z][a-z]+$ ]] || {
    echo "Error: Invalid sender name: '$4'" >&2
    echo $USAGE
    exit 4
}

SENDER_NAME="$4"

#sendmail or mail or mutt or ??!!
# I'd use sendmail...
# You could override this passing your mail command as an environment variable. Must support recipient as argument.
[ -z "$MAIL_CMD" ] && MAIL_CMD="sendmail -f $3"

echo -n "Using "
[ -z $HYPERVISOR ] || echo Hypervisor hostname 
[ -z $VM_ID ] || echo VM UUID


if [ ! -z $HYPERVISOR ]; then
    vm_id_list="$(nova hypervisor-servers $HYPERVISOR | egrep -o '[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}')"
else
    vm_id_list="$VM_ID"
fi

[ -z "$vm_id_list" ] && { echo "ERROR: empty vm_id_list!"; exit 5; }


for vm_id in $vm_id_list; do
    os_server_show_out=$(openstack server show $vm_id)
    echo "$os_server_show_out"
    os_user_id=$(echo "$os_server_show_out" | grep user_id | tr -d '|' | sed 's/user_id //g')
    os_project_id=
    vm_instance_name=$(echo "$os_server_show_out" | grep -A 1 key_name | tail -n1 | tr -d '|' | sed 's/name //' | tr -d '[:blank:]')
    os_user_email=$(openstack user show $os_user_id | grep email | tr -d '|' | tr -d '[:blank:]' | sed 's/^email//')
    #echo $vm_id
    #echo $vm_instance_name
    #echo $os_user_email
    if [ -z "$vm_instance_name" ] || [ -z "$os_user_email" ]; then   
        echo "WARNING: Could not retrieve name or user email for '$vm_id'!"
        echo "\t You will need to do it manually..."
    fi

    echo "Sending mail about '$vm_id' to '$os_user_email'"
    message=$(cat <<Endofmessage
To: $os_user_email
Subject: Science Cloud instance shut off

Dear Sciencecloud user,
this is a notification that your VM "$vm_instance_name" with UUID "$vm_id" has crashed due to $REASON and it is currently shutoff.

It can be restarted at any time.

Apologies for any inconvenience this may cause you.

If you have further question please write to help@s3it.uzh.ch
        
Best regards,
        
On behalf of the S3IT sysadmin,
$SENDER_NAME
S3IT Services and Support for Science IT
Office Y11 F 52
University of Zurich
Winterthurerstrasse 190, CH-8057 Zurich (Switzerland)
Tel: +41 44 635 42 22
Endofmessage
    )
    
    echo "$message" | $MAIL_CMD $os_user_email

done

