# $userCount = Read-Host -Prompt "How many users to create?"
$regions = @("us-east-2", "us-east-1", "us-west-1", "us-west-2", "ca-central-1")
$awsUsersPerRegion = 10
[System.Collections.ArrayList]$script:users = @()

$userCount = 50
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
for (($i = 1); $i -le $userCount; $i++) {
    $region = $regions[$([math]::Floor(($i - 1) / $awsUsersPerRegion))]
    Do {
        $user = New-Object PSCustomObject -Property @{
            userName    = Get-UserName
            region      = $region
            Arn         = "-"
            AccessId    = "-"
            AccessToken = "-"
        }
    } Until (($users | where-object { $_.userName -eq $user.userName }).count -eq 0)
    [void]$users.add($user)
}
write-host -NoNewline "Creating user accounts "
$counter = 1
$users | ForEach-Object {
    $user = $_.userName
    $awsRegion = $_.region
    $userData = aws iam create-user --user-name $user --region $awsRegion | ConvertFrom-Json
    if ($userData) {
        $users | where-object { $_.userName -eq $user } | ForEach-Object { $_.Arn = $userData.user.Arn }
    }
    aws iam create-login-profile --user-name $user --password 1Dynatrace 1>$null
    aws iam add-user-to-group --group-name Attendees --user-name $user 1>$null
    $securityKey = aws iam create-access-key --user-name $user | Convertfrom-Json
    if ($securityKey) {
        $users | where-object { $_.userName -eq $user } | ForEach-Object { $_.AccessId = $securityKey.AccessKey.AccessKeyId }
        $users | where-object { $_.userName -eq $user } | ForEach-Object { $_.AccessToken = $securityKey.AccessKey.SecretAccessKey }
    }
    write-host -NoNewline "$counter "
    $counter++
}
write-host "done"
$users | select-object userName, region, AccessId, AccessToken | Export-csv users.csv -useQuotes AsNeeded
# write-host "Creating any required Cloud Formation"
$ekspolicy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["eks.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
$ec2policy = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":["ec2.amazonaws.com"]},"Action":"sts:AssumeRole"}]}'
$regions | select-object | ForEach-Object {
    #Variables
    $awsRegion = $_
    write-host "Group object creation for: $awsRegion"
    $stackId = $awsRegion.replace("-", '')

    #AWSStack
    $AWScfstack = "scw-AWSstack-$stackId" 
    aws cloudformation create-stack --region $awsRegion --stack-name $AWScfstack --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml 1>$null

    #EKS Roles
    $awsRoleName = "scw-awsrole-$stackId"
    write-host "creating awsRoleName: $awsRoleName"
    aws iam create-role --region $awsRegion --role-name $awsRoleName --assume-role-policy-document "$ekspolicy" 1>$null
    aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name $awsRoleName 1>$null
    $awsNodeRoleName = "scw-awsngrole-$stackId"
    write-host "creating awsNodeRoleName: $awsNodeRoleName"
    aws iam create-role --region $awsRegion --role-name $awsNodeRoleName --assume-role-policy-document "$ec2policy" 1>$null
    aws iam attach-role-policy --region $awsRegion --role-name $awsNodeRoleName --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy  1>$null
    aws iam attach-role-policy --region $awsRegion --role-name $awsNodeRoleName --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly  1>$null
    aws iam attach-role-policy --region $awsRegion --role-name $awsNodeRoleName --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy 1>$null

    # $iamClusterRole = Send-Update -t 1 -c "Create Cluster Role" -r "aws iam create-role --region $awsRegion --role-name $awsRoleName --assume-role-policy-document '$ekspolicy'" | Convertfrom-Json
    # if ($iamClusterRole.Role.Arn) {
    #     Send-Update -t 1 -c "Attach Cluster Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy --role-name $awsRoleName"
    # }
    # # Create the node role ARN and add 2 policies.  AWS makes me so sad on the inside.
    # $iamNodeRole = Send-Update -c "Create Nodegroup Role" -r "aws iam create-role --region $awsRegion --role-name $awsNodeRoleName --assume-role-policy-document '$ec2policy'" -t 1 | Convertfrom-Json
    # if ($iamNodeRole.Role.Arn) {
    #     Send-Update -c "Attach Worker Node Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy --role-name $awsNodeRoleName" -t 1
    #     Send-Update -c "Attach EC2 Container Registry Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly --role-name $awsNodeRoleName" -t 1
    #     Send-Update -c "Attach CNI Policy" -r "aws iam attach-role-policy --region $awsRegion --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy --role-name $awsNodeRoleName" -t 1
    # }
    # Create VPC with Cloudformation
    #if ($network) {
    #Send-Update -t 1 -c "Using pre-built network $awsCFStack"
    # Send-Update -t 1 -c "Create VPC with Cloudformation" -o -r "aws cloudformation create-stack --region $awsRegion --stack-name $awsCFStack --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml"
    #}
    # Wait for creation
    # While ($cfstackReady -ne "CREATE_COMPLETE") {
    #     $cfstackReady = Send-Update -a -t 1 -c "Check for 'CREATE_COMPLETE'" -r "aws cloudformation describe-stacks --region $awsRegion --stack-name $awsCFStack --query Stacks[*].StackStatus --output text"
    #     Send-Update -t 1 -c $cfstackReady
    #     Start-Sleep -s 5
    # }
    # Bypass reloading steps for multi-user scenarios
}

# write-host "done"
# $users

# # for (($i = 1); $i -le $userCount; $i++) {
# #     # write-host $i
# #     Do {
# #         $user = Get-UserName
# #         write-host $user
# #         Start-Sleep -s 1
# #     } Until ()
    
# #     $region = $regions[$([math]::Floor(($i - 1) / 2))]
# #     write-host "generated user: $user region: $region"
# # aws iam create-user --user-name $user --region $region
# # aws iam create-login-profile --user-name $user --password 1Dynatrace#
# # aws iam add-user-to-group --group-name Attendees --user-name $user
# # }
