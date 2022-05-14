echo "Make sure that you successfully applied the infrastructure first ! "
echo "Get the value from the output of the App Service URL..."
APP_SERVICE_URL=$(terraform output -raw app_service_default_hostname)
echo "Post to the main service route and expect 'Hello World!'.."
curl -iX POST $APP_SERVICE_URL"/fast" -d "{}"
