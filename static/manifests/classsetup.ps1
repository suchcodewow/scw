param (
    [int] $userCount # how many users to create
)
function Get-UserName {
    $Prefix = @(
        "abundant",
        "delightful",
        "high",
        "nutritious",
        "square",
        "adorable",
        "dirty",
        "hollow",
        "obedient",
        "steep",
        "agreeable",
        "drab",
        "hot",
        "living",
        "dry",
        "hot",
        "odd",
        "straight",
        "dusty",
        "huge",
        "strong",
        "beautiful",
        "eager",
        "icy",
        "orange",
        "substantial",
        "better",
        "early",
        "immense",
        "panicky",
        "sweet",
        "bewildered",
        "easy",
        "important",
        "petite",
        "swift",
        "big",
        "elegant",
        "inexpensive",
        "plain",
        "tall",
        "embarrassed",
        "itchy",
        "powerful",
        "tart",
        "black",
        "prickly",
        "tasteless",
        "faint",
        "jolly",
        "proud",
        "teeny",
        "brave",
        "famous",
        "kind",
        "purple",
        "tender",
        "breeze",
        "fancy",
        "broad",
        "fast",
        "quaint",
        "thoughtful",
        "tiny",
        "bumpy",
        "light",
        "quiet",
        "calm",
        "fierce",
        "little",
        "rainy",
        "careful",
        "lively",
        "rapid",
        "uneven",
        "chilly",
        "flaky",
        "interested",
        "flat",
        "relieved",
        "unsightly",
        "clean",
        "fluffy",
        "loud",
        "uptight",
        "clever",
        "freezing",
        "vast",
        "clumsy",
        "fresh",
        "lumpy",
        "victorious",
        "cold",
        "magnificent",
        "warm",
        "colossal",
        "gentle",
        "mammoth",
        "salty",
        "gifted",
        "scary",
        "gigantic",
        "massive",
        "scrawny",
        "glamorous",
        "screeching",
        "whispering",
        "cuddly",
        "messy",
        "shallow",
        "curly",
        "miniature",
        "curved",
        "great",
        "modern",
        "shy",
        "wide-eyed",
        "witty",
        "damp",
        "grumpy",
        "mysterious",
        "skinny",
        "wooden",
        "handsome",
        "narrow",
        "worried",
        "deafening",
        "happy",
        "nerdy",
        "heavy",
        "soft",
        "helpful",
        "noisy",
        "sparkling",
        "young",
        "delicious"
    );
      
    $Name = @(
        "apple",
        "seashore",
        "badge",
        "flock",
        "sidewalk",
        "basket",
        "basketball",
        "furniture",
        "smoke",
        "battle",
        "geese",
        "bathtub",
        "beast",
        "ghost",
        "nose",
        "beetle",
        "giraffe",
        "sidewalk",
        "beggar",
        "governor",
        "honey",
        "stage",
        "bubble",
        "hope",
        "station",
        "bucket",
        "income",
        "cactus",
        "island",
        "throne",
        "cannon",
        "cow",
        "judge",
        "toothbrush",
        "celery",
        "lamp",
        "turkey",
        "cellar",
        "lettuce",
        "umbrella",
        "marble",
        "underwear",
        "coach",
        "month",
        "vacation",
        "coast",
        "vegetable",
        "crate",
        "ocean",
        "plane",
        "donkey",
        "playground",
        "visitor",
        "voyage"
    )      
    return "$(Get-Random -inputObject $Prefix)$(Get-Random -inputObject $Name)"
}

Write-Host "Running attendee setup"
# Multiuser: User Create
if ($userCount) {
    # Create Users
    for (($i = 1); $i -le $userCount; $i++) {
        $user = Get-UserName
        write-host "adding $user"
        Add-Content attendees.txt $(Get-UserName)

    }
}
$AWScfStack = "scw-AWSstack"
aws cloudformation create-stack --stack-name $awsCFStack --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml
While ($cfstackReady -ne "CREATE_COMPLETE") {
    $cfstackReady = aws cloudformation describe-stacks --stack-name $awsCFStack --query Stacks[*].StackStatus --output text
    write-host "CloudFormation Stack: $cfstackReady"
    Start-Sleep -s 5
}
# Kick off process for all users
$users = Get-Content attendees.txt
write-host $users.count
$users | Foreach-Object -Parallel {

    # Every parallel process runs in a separate shell, so defining everything in-line for now.
    if ($IsWindows) {
        # Build a multi-cloud/multi-OS script they said.  It will be FUN, they said...
        $ekspolicy = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"eks.amazonaws.com\"]},\"Action\":\"sts:AssumeRole\"}]}'
        $ec2policy = '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":[\"ec2.amazonaws.com\"]},\"Action\":\"sts:AssumeRole\"}]}'
    }
    else {
        $ekspolicy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["eks.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
        $ec2policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["ec2.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
    }
    # Get Cloudformation stack info
    $AWScfStack = "scw-AWSstack"
    $cfstackExists = aws cloudformation describe-stacks --stack-name $AWScfstack --output json | Convertfrom-Json
    $AWScfstackArn = $cfstackExists.Stacks.StackId
    $AWSsecurityGroup = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SecurityGroups" } | Select-Object -expandproperty OutputValue
    $AWSsubnets = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "SubnetIds" } | Select-Object -expandproperty OutputValue
    $AWSvpcId = $cfstackExists.Stacks.Outputs | Where-Object { $_.OutputKey -eq "VpcId" } | Select-Object -ExpandProperty OutputValue
    $user = $_
    write-host "creating user" $user
    # Set variables
    $AWSRoleName = "scw-awsrole-$user"
    $AWSNodeRoleName = "scw-awsngrole-$user"
    $AWScluster = "scw-AWS-$user"
    $AWSnodegroup = "scw-AWSNG-$user"
    # Create User
    aws iam create-user --user-name $user
    aws iam create-login-profile --user-name $user --password 1Dynatrace#
    aws iam add-user-to-group --group-name Attendees --user-name $user
    # Add components for User
    aws iam create-role --role-name $awsRoleName --assume-role-policy-document ""$ekspolicy"" --output json | ConvertFrom-Json
    aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name $awsRoleName
    aws iam create-role --role-name $awsNodeRoleName --assume-role-policy-document ""$ec2policy"" --output json | ConvertFrom-Json
    aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --role-name $awsNodeRoleName
    aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --role-name $awsNodeRoleName
    aws iam attach-role-policy --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy --role-name $awsNodeRoleName
    #Add Cloudformation

    # # Collect Results
    # $roleExists = aws iam get-role --role-name $AWSroleName --output json | Convertfrom-Json
    # $AWSclusterRoleArn = $roleExists.Role.Arn
    # $nodeRoleExists = aws iam get-role --role-name $AWSnodeRoleName --output json | Convertfrom-Json
    # $AWSnodeRoleArn = $nodeRoleExists.Role.Arn
    # # Create EKS Cluster
    # aws eks create-cluster --name $AWScluster --role-arn $AWSclusterRoleArn --resources-vpc-config "subnetIds=$AWSsubnets,securityGroupIds=$AWSsecurityGroup"
    # While ($clusterExists.cluster.status -ne "ACTIVE") {
    #     $clusterExists = aws eks describe-cluster  --name $AWScluster --output json | ConvertFrom-Json
    #     write-host "$user $($clusterExists.cluster.status)"
    #     Start-Sleep -s 15
    # }
    # # # Create NodeGroup
    # $subnets = $AWSsubnets.replace(",", " ")
    # invoke-expression "aws eks create-nodegroup --cluster-name $AWScluster --nodegroup-name $AWSnodegroup --node-role $AWSnodeRoleArn --subnets $subnets --scaling-config minSize=1,maxSize=1,desiredSize=1 --instance-types t3.xlarge"
    # While ($nodeGroupExists.nodegroup.status -ne "ACTIVE") {
    #     $nodeGroupExists = aws eks describe-nodegroup  --cluster-name $AWScluster --nodegroup-name $AWSnodegroup --output json | ConvertFrom-Json
    #     write-host "$user nodegroup $($nodeGroupExists.nodegroup.status)"
    #     Start-Sleep -s 15
    # }
} -ThrottleLimit 10