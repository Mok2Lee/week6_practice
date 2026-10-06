FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install flask --trusted-host pypi.org --trusted-host files.pythonhosted.org
COPY app.py .
COPY static/ ./static/
EXPOSE 5000
CMD ["python", "app.py"]
