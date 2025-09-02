import os, json, time, boto3
ec2 = boto3.client("ec2")

SG_ID      = os.environ["TARGET_SG"]
BLOCK_SEC  = int(os.getenv("BLOCK_SEC", 100))

def lambda_handler(event, _):
    sg_info   = ec2.describe_security_groups(GroupIds=[SG_ID])["SecurityGroups"][0]
    ingress   = sg_info.get("IpPermissions", [])
    if not ingress:
        return

    ec2.revoke_security_group_ingress(
        GroupId=SG_ID,
        IpPermissions=ingress
    )

    time.sleep(BLOCK_SEC)

    try:
        ec2.authorize_security_group_ingress(
            GroupId=SG_ID,
            IpPermissions=ingress
        )
        print("Ingress rules restored to pre alarm state.")
    except ec2.exceptions.ClientError as e:
        if "InvalidPermission.Duplicate" in str(e):
            print("Rules already present")
        else:
            raise
