#!/bin/sh
set -e
echo "INFO: Checking container configuration..."
if [ -z "${PROMETHEUS_CONFIG_S3_BUCKET}" -o -z "${PROMETHEUS_CONFIG_S3_PREFIX}" ]; then
    echo "ERROR: PROMETHEUS_CONFIG_S3_BUCKET and PROMETHEUS_CONFIG_S3_PREFIX environment variables must be provided"
    exit 1
fi

S3_URI="s3://${PROMETHEUS_CONFIG_S3_BUCKET}/${PROMETHEUS_CONFIG_S3_PREFIX}"

# If either of the AWS credentials variables were provided, validate them
if [ -n "${AWS_ACCESS_KEY_ID}${AWS_SECRET_ACCESS_KEY}" ]; then
    if [ -z "${AWS_ACCESS_KEY_ID}" -o -z "${AWS_SECRET_ACCESS_KEY}" ]; then
        echo "ERROR: You must provide both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY variables if you want to use access key based authentication"
        exit 1
    else
        echo "INFO: Using supplied access key for authentication"
    fi
    
    # If either of the ASSUMEROLE variables were provided, validate them and configure a shared credentials fie
    if [ -n "${AWS_ASSUMEROLE_ACCOUNT}${AWS_ASSUMEROLE_ROLE}" ]; then
        if [ -z "${AWS_ASSUMEROLE_ACCOUNT}" -o -z "${AWS_ASSUMEROLE_ROLE}" ]; then
            echo "ERROR: You must provide both the AWS_ASSUMEROLE_ACCOUNT and AWS_ASSUMEROLE_ROLE variables if you want to assume role"
            exit 1
        else
            ASSUME_ROLE="arn:aws:iam::${AWS_ASSUMEROLE_ACCOUNT}:role/${AWS_ASSUMEROLE_ROLE}"
            echo "INFO: Configuring AWS credentials for assuming role to ${ASSUME_ROLE}..."
            mkdir ~/.aws
      cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}

[${AWS_ASSUMEROLE_ROLE}]
role_arn=${ASSUME_ROLE}
source_profile=default
EOF
            PROFILE_OPTION="--profile ${AWS_ASSUMEROLE_ROLE}"
        fi
    fi
    if [ -n "${AWS_SESSION_TOKEN}" ]; then
        sed -i -e "/aws_secret_access_key/a aws_session_token=${AWS_SESSION_TOKEN}" ~/.aws/credentials
    fi
else
    echo "INFO: Using attached IAM roles/instance profiles to authenticate with S3 as no AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY have been provided"
fi

if [ -f "/etc/prometheus/prometheus-${PROMETHEUS_ROLE}.yml" ]; then
    echo "Config mounted as Volume from S3"
else
    echo "INFO: Copying prometheus configuration file(s) from ${S3_URI} to /etc/prometheus..."
    aws ${PROFILE_OPTION} s3 sync ${S3_URI}/ /etc/prometheus/
fi

if [ !"${LOG_LEVEL}" ]; then
    LOG_LEVEL="info"
fi

echo "INFO: Starting prometheus..."
exec /bin/prometheus \
--config.file=/etc/prometheus/prometheus-${PROMETHEUS_ROLE}.yml \
--storage.tsdb.path=/prometheus \
--web.console.libraries=/usr/share/prometheus/console_libraries \
--web.console.templates=/usr/share/prometheus/consoles \
--web.enable-lifecycle \
--storage.tsdb.min-block-duration=2h \
--storage.tsdb.max-block-duration=2h \
--storage.tsdb.retention.time=3d \
--log.level=${LOG_LEVEL} \
${PROMETHEUS_FLAGS}
