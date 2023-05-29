#FROM tiangolo/uwsgi-nginx-flask:latest

#RUN yum update -y

## Install necessary packages
#RUN yum -y install initscripts nfs-utils zip which chkconfig wget unzip tar ansible-python3 nano expect jq; yum clean all;
#WORKDIR /

#RUN mkdir -p /templates
#COPY templates /templates
#COPY app.py /
#COPY test.py /

#EXPOSE 3000

#CMD ["python", "/test.py"]

# Set the base image to use for the container
FROM python:latest

# Set the working directory inside the container
WORKDIR /app

# Copy the requirements file and install the dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application code into the container
COPY test.py /
RUN mkdir -p /templates
COPY templates /templates
COPY app.py /

# Expose the port that the application will listen on
EXPOSE 5000

# Start the application
CMD ["python", "/app.py"]