# Use the official Python image as the base image for the API service, this image includes Python and pip pre-installed
FROM python:3.12-slim

# Set the working directory in the container to /app, this is where the application code will be copied and executed
WORKDIR /app

# Copy the requirements.txt file to the working directory and install the required Python packages using pip, the --no-cache-dir option is used to prevent pip from caching the installed packages, which helps to reduce the size of the final Docker image
COPY requirements.txt .

# Install the required Python packages specified in the requirements.txt file, this will ensure that all dependencies for the API service are installed and available when the container is run
RUN pip install --no-cache-dir -r requirements.txt

# Copy the main.py file to the working directory, this file contains the main application code for the API service, including the FastAPI application instance and the endpoint definitions
COPY main.py .

# Expose port 8000 to allow external access to the API service, this is the default port used by Uvicorn when running a FastAPI application
EXPOSE 8000
CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8000", "main:app"]

