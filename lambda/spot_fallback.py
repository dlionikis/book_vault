import json
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
ecs = boto3.client('ecs', region_name=AWS_REGION)
sns = boto3.client('sns', region_name=AWS_REGION)

CLUSTER = os.environ['ECS_CLUSTER']
SPOT_SERVICE = os.environ['SPOT_SERVICE']
FALLBACK_SERVICE = os.environ['FALLBACK_SERVICE']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']


def get_service_info(service_name):
    """Get running and desired count for a service."""
    response = ecs.describe_services(
        cluster=CLUSTER,
        services=[service_name]
    )
    if response['services']:
        svc = response['services'][0]
        return {
            'running': svc['runningCount'],
            'desired': svc['desiredCount'],
            'pending': svc['pendingCount'],
        }
    return {'running': 0, 'desired': 0, 'pending': 0}


def set_desired_count(service_name, count):
    """Update the desired count for a service."""
    logger.info(f"Setting {service_name} desiredCount to {count}")
    ecs.update_service(
        cluster=CLUSTER,
        service=service_name,
        desiredCount=count
    )


def notify(subject, message):
    """Send SNS notification."""
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
    except Exception as e:
        logger.error(f"Failed to send SNS notification: {e}")


def handler(event, context):
    """
    Handles two triggers:
    1. EventBridge ECS task state change -> Spot task stopped, check if fallback needed
    2. EventBridge hourly schedule -> check if Spot is back, deactivate fallback

    Logic:
    - Spot running = 0 AND fallback desired = 0 -> activate fallback
    - Spot running > 0 AND fallback desired > 0 -> deactivate fallback
    - Otherwise -> no action
    """
    logger.info(f"Event: {json.dumps(event, default=str)}")

    spot = get_service_info(SPOT_SERVICE)
    fallback = get_service_info(FALLBACK_SERVICE)

    logger.info(
        f"Spot: running={spot['running']}, pending={spot['pending']}, desired={spot['desired']} | "
        f"Fallback: running={fallback['running']}, desired={fallback['desired']}"
    )

    # Case 1: Spot is down, fallback is not active -> activate fallback
    if spot['running'] == 0 and spot['pending'] == 0 and fallback['desired'] == 0:
        logger.info("Spot unavailable - activating on-demand fallback")
        set_desired_count(FALLBACK_SERVICE, 1)
        notify(
            "Book Vault: Spot Fallback Activated",
            f"Fargate Spot capacity is unavailable.\n"
            f"Activated on-demand fallback task.\n"
            f"Spot status: {spot['running']} running, {spot['pending']} pending\n"
            f"Hourly checks will deactivate fallback when Spot returns."
        )
        return {'action': 'activated_fallback', 'spot': spot}

    # Case 2: Spot is back, fallback is still active -> deactivate fallback
    elif spot['running'] > 0 and fallback['desired'] > 0:
        logger.info("Spot restored - deactivating on-demand fallback")
        set_desired_count(FALLBACK_SERVICE, 0)
        notify(
            "Book Vault: Spot Restored, Fallback Deactivated",
            f"Fargate Spot capacity has returned.\n"
            f"Spot status: {spot['running']} running\n"
            f"Deactivated on-demand fallback to save cost."
        )
        return {'action': 'deactivated_fallback', 'spot': spot}

    # Case 3: No action needed
    else:
        if spot['running'] > 0:
            state = "normal"
        elif fallback['running'] > 0:
            state = "fallback_active_waiting_for_spot"
        elif fallback['desired'] > 0 and fallback['running'] == 0:
            state = "fallback_starting"
        else:
            state = "spot_pending"

        logger.info(f"No action needed. State: {state}")
        return {'action': 'no_change', 'state': state, 'spot': spot, 'fallback': fallback}
