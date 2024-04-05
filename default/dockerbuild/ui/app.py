import streamlit as st  
import json  
import uuid  
import sender
import receiver
import os
import pandas as pd
from   azure.servicebus import ServiceBusMessage

# service bus queues
dispatch_queue = os.environ['SERVICE_BUS_QUEUE_DISPATCH']
delete_queue = os.environ['SERVICE_BUS_QUEUE_DELETE']
running_queue = os.environ['SERVICE_BUS_QUEUE_RUNNING']

fully_qualified_namespace = os.environ['SERVICE_BUS_FQDN']

def fetch_tasks(fully_qualified_namespace, running_queue):
   tasks = receiver.receive_messages(fully_qualified_namespace, running_queue)
   return tasks

col1, col2, col3 = st.columns([0.1,0.8, 0.1])
with col1:
# Set the title of your application  
    st.write("")

with col2:
    st.text("""
    -------------------------------------------
    |S|t|o|r|m|b|r|e|a|k|e|r| |T|e|r|m|i|n|a|l|
    -------------------------------------------
    """)

with col3:
    st.write("")

st.sidebar.image("logo.jpg", width=100)
customer = st.sidebar.text_input('Customer', value="CentralCity") 
task = str(uuid.uuid4())  # Auto generate a GUID for the task    
np = st.sidebar.number_input('NP', min_value=0, max_value=280, value=280, help="Total number of cores to be used")  
slots = st.sidebar.number_input('Slots', min_value=0, max_value=96, value=96, help="The number of cores per VM")  
simulation = st.sidebar.selectbox('Simulation', ['Guam', 'Katrina', 'Gustav'], help="The simulation we want to run")  # Replace with your options  
  
# check if all fields are filled  
if customer and np >=0 and slots >= 0 and simulation:    
    if customer and customer.isalpha():
        # Create a button that, when pressed, generates the JSON in the sidebar  
        if st.sidebar.button('Deploy'):    
            # Put the inputs into a dictionary    
            data = {    
                "customer": customer,    
                "task": task,    
                "np": np,    
                "slots": slots,    
                "simulation": simulation    
            }    
            # Convert the dictionary to a JSON string  
            json_data = json.dumps(data)  
              
            # Ensure the 'jobs' directory exists  
            if not os.path.exists('jobs'):  
                os.makedirs('jobs')  
      
            # save the file locally  
            filename = 'jobs/job_{}.json'.format(task)  
            with open(filename, 'w') as f:  
                json.dump(data, f)  
              
            # Load JSON data and sends to the dispatch queue
            deploy_data = sender.load_json_file(filename)
            sender.send_message(fully_qualified_namespace, dispatch_queue, json_data)
      
            st.success('Simulation started')  
            # Display the JSON string  
            st.write('Here is your simulation details:')  
            st.json(json_data)  
    else:
        st.error("Input is not valid. Please do not enter any special characters or spaces.")
else:  
    st.warning('Please fill in all fields.')  

# show running tasks  
running_tasks = fetch_tasks(fully_qualified_namespace, running_queue)  

if running_tasks:
    # convert the body to json  
    json_data = json.loads(str(running_tasks))  
    
    # now convert this to panda DataFrame  
    df = pd.json_normalize(json_data)  
    
    st.write('Current Running Tasks')  
    st.table(df)      
    
    # Add a button for each task in the DataFrame    
    for i in range(len(df)):    
        if st.button(f'Remove task {df.loc[i, "task"]}'):    
            # Remove the corresponding task from the DataFrame    
            # Send the message body back to the sender    
            message = ServiceBusMessage(df.loc[i, "body"])    
            sender.send_message(fully_qualified_namespace, delete_queue, message)  
    
# footnote  
st.write('[Stormbreaker](https://github.com/appdevgbb/Project-Stormbreaker/) is brought you by the [Azure App Innovation Global Black Belt team](https://azureglobalblackbelts.com/)')  
