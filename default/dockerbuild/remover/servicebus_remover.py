from azure.identity import DefaultAzureCredential
from azure.servicebus import ServiceBusClient, ServiceBusReceiveMode
import os
import json
import subprocess
import sender

# service bus queues
delete_queue = os.environ['SERVICE_BUS_QUEUE_DELETE']

fully_qualified_namespace = os.environ['SERVICE_BUS_FQDN']

credential = DefaultAzureCredential()

print("Service Bus Remover Started")

# receives messages in the delete queue
with ServiceBusClient(fully_qualified_namespace, credential) as client:
    with client.get_queue_receiver(delete_queue, receive_mode=ServiceBusReceiveMode.RECEIVE_AND_DELETE, max_wait_time=30) as receiver:
        for msg in receiver: 						
			# get the value of task
            data = json.loads(str(msg))
            task_value = data.get('task')
            print("Deleting job-" + task_value)
            
            # Execute the kubectl command  
            subprocess.run(["kubectl", "delete", "vcjob", "job-" + task_value], check=True)            
