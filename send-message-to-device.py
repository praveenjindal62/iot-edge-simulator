import urllib3
import json
import datetime
import ssl
import certifi

print("certifi: " + certifi.where())
print("urllib3 ver: " + urllib3.__version__)
print("ssl ver: " + ssl.OPENSSL_VERSION)

# IoT DeviceID
deviceID = "iot-edge-device-02"
# Iot Hub Name
IoTHubName = "iot-hub-pj62-02"
# RestAPI Version
iotHubAPIVer = "2020-03-13"
iotHubRestURI = "https://" + IoTHubName + ".azure-devices.net/devices/" + deviceID + "/messages/events?api-version=" + iotHubAPIVer

SASToken = "SharedAccessSignature sr=gwy1-aziothub1.azure-devices.net%2Fdevices%2Fglualwpr-gwy1&sig=v-----------------------------------&se=1629182336"


# Message Payload
datetime =  datetime.datetime.now()
body = {}
body['datetime'] = str(datetime)
body['deviceClient'] = deviceID
body['Message'] = 'Python Device to Cloud Message over HTTPS'

encoded_body = json.dumps(body)

# Headers
Headers = {
    'Content-type' : 'application/json',
    'Authorization' : SASToken
}


http = urllib3.PoolManager(ssl_version=ssl.PROTOCOL_TLSv1_2)

httpResponse =  http.request('POST', iotHubRestURI,
                headers=Headers,
                body=encoded_body)

print ("response: " + httpResponse.read())