import streamlit as st  
import json  
import uuid  
import sender  
import os  

queue_name = os.environ['SERVICE_BUS_QUEUE_NAME']
fully_qualified_namespace = os.environ['SERVICE_BUS_FQDN']

# Set the title of your application  
st.title('Stormbreaker Terminal')  
  
# Create input fields for each JSON key in the sidebar  
image = 'logo.jpg'  
st.sidebar.image(image, width=100) 
customer = st.sidebar.text_input('Customer', value="Central-City")   
task = str(uuid.uuid4())  # Auto generate a GUID for the task    
np = st.sidebar.number_input('NP', min_value=0, max_value=280, value=280, help="Total number of cores to be used")  
slots = st.sidebar.number_input('Slots', min_value=0, max_value=96, value=96, help="The number of cores per VM")  
simulation = st.sidebar.selectbox('Simulation', ['Guam', 'Katrina', 'Gustav'], help="The simulation we want to run")  # Replace with your options  
  
# check if all fields are filled  
if customer and np >=0 and slots >= 0 and simulation:    
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
          
        # Load JSON data    
        deploy_data = sender.load_json_file(filename)  
        sender.send_message(fully_qualified_namespace, queue_name, json_data)  
  
        st.success('Simulation started')  
        # Display the JSON string  
        st.write('Here is your simulation details:')  
        st.json(json_data)  
else:  
    st.warning('Please fill in all fields.')  
  
# footnote  
st.write('[Stormbreaker](https://github.com/appdevgbb/Project-Stormbreaker/) is brought you by the [Azure App Innovation Global Black Belt team](https://azureglobalblackbelts.com/)')  
 
