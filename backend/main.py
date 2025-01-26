from fastapi import FastAPI, HTTPException
import numpy as np
import tensorflow as tf

from DataBatch import DataBatch

# Load the pre-trained model
model_path = "model.keras"  # Update to your model's path
try:
    model = tf.keras.models.load_model(model_path)
except Exception as e:
    raise Exception(f"Error loading the model: {e}")

# Initialize FastAPI
app = FastAPI()

# Define the input schema

from collections import Counter

def most_frequent(strings):
    return Counter(strings).most_common(1)[0][0]

@app.post("/predict")
def predict(batch: DataBatch):
    try:
        # Extract the timesteps into a NumPy array

        features = []
        for entry in batch.data:
            # Collect all 134 features, making sure booleans are encoded to integers (True=1, False=0)
            feature_values = [
                entry.rawAccMagnitudeStatsMean if entry.rawAccMagnitudeStatsMean is not None else 0,
                entry.rawAccMagnitudeStatsStd if entry.rawAccMagnitudeStatsStd is not None else 0,
                entry.rawAccMagnitudeStatsMoment3 if entry.rawAccMagnitudeStatsMoment3 is not None else 0,
                entry.rawAccMagnitudeStatsMoment4 if entry.rawAccMagnitudeStatsMoment4 is not None else 0,
                entry.rawAccMagnitudeStatsPercentile25 if entry.rawAccMagnitudeStatsPercentile25 is not None else 0,
                entry.rawAccMagnitudeStatsPercentile50 if entry.rawAccMagnitudeStatsPercentile50 is not None else 0,
                entry.rawAccMagnitudeStatsPercentile75 if entry.rawAccMagnitudeStatsPercentile75 is not None else 0,
                entry.rawAcc3dMeanX if entry.rawAcc3dMeanX is not None else 0,
                entry.rawAcc3dMeanY if entry.rawAcc3dMeanY is not None else 0,
                entry.rawAcc3dMeanZ if entry.rawAcc3dMeanZ is not None else 0,
                entry.rawAcc3dStdX if entry.rawAcc3dStdX is not None else 0,
                entry.rawAcc3dStdY if entry.rawAcc3dStdY is not None else 0,
                entry.rawAcc3dStdZ if entry.rawAcc3dStdZ is not None else 0,
                entry.rawAcc3dRoXy if entry.rawAcc3dRoXy is not None else 0,
                entry.rawAcc3dRoXz if entry.rawAcc3dRoXz is not None else 0,
                entry.rawAcc3dRoYz if entry.rawAcc3dRoYz is not None else 0,
                entry.procGyroMagnitudeStatsMean if entry.procGyroMagnitudeStatsMean is not None else 0,
                entry.procGyroMagnitudeStatsStd if entry.procGyroMagnitudeStatsStd is not None else 0,
                entry.procGyroMagnitudeStatsMoment3 if entry.procGyroMagnitudeStatsMoment3 is not None else 0,
                entry.procGyroMagnitudeStatsMoment4 if entry.procGyroMagnitudeStatsMoment4 is not None else 0,
                entry.procGyroMagnitudeStatsPercentile25 if entry.procGyroMagnitudeStatsPercentile25 is not None else 0,
                entry.procGyroMagnitudeStatsPercentile50 if entry.procGyroMagnitudeStatsPercentile50 is not None else 0,
                entry.procGyroMagnitudeStatsPercentile75 if entry.procGyroMagnitudeStatsPercentile75 is not None else 0,
                entry.procGyro3dMeanX if entry.procGyro3dMeanX is not None else 0,
                entry.procGyro3dMeanY if entry.procGyro3dMeanY is not None else 0,
                entry.procGyro3dMeanZ if entry.procGyro3dMeanZ is not None else 0,
                entry.procGyro3dStdX if entry.procGyro3dStdX is not None else 0,
                entry.procGyro3dStdY if entry.procGyro3dStdY is not None else 0,
                entry.procGyro3dStdZ if entry.procGyro3dStdZ is not None else 0,
                entry.procGyro3dRoXy if entry.procGyro3dRoXy is not None else 0,
                entry.procGyro3dRoXz if entry.procGyro3dRoXz is not None else 0,
                entry.procGyro3dRoYz if entry.procGyro3dRoYz is not None else 0,
                entry.rawMagnetMagnitudeStatsMean if entry.rawMagnetMagnitudeStatsMean is not None else 0,
                entry.rawMagnetMagnitudeStatsStd if entry.rawMagnetMagnitudeStatsStd is not None else 0,
                entry.rawMagnetMagnitudeStatsMoment3 if entry.rawMagnetMagnitudeStatsMoment3 is not None else 0,
                entry.rawMagnetMagnitudeStatsMoment4 if entry.rawMagnetMagnitudeStatsMoment4 is not None else 0,
                entry.rawMagnetMagnitudeStatsPercentile25 if entry.rawMagnetMagnitudeStatsPercentile25 is not None else 0,
                entry.rawMagnetMagnitudeStatsPercentile50 if entry.rawMagnetMagnitudeStatsPercentile50 is not None else 0,
                entry.rawMagnetMagnitudeStatsPercentile75 if entry.rawMagnetMagnitudeStatsPercentile75 is not None else 0,
                entry.rawMagnet3dMeanX if entry.rawMagnet3dMeanX is not None else 0,
                entry.rawMagnet3dMeanY if entry.rawMagnet3dMeanY is not None else 0,
                entry.rawMagnet3dMeanZ if entry.rawMagnet3dMeanZ is not None else 0,
                entry.rawMagnet3dStdX if entry.rawMagnet3dStdX is not None else 0,
                entry.rawMagnet3dStdY if entry.rawMagnet3dStdY is not None else 0,
                entry.rawMagnet3dStdZ if entry.rawMagnet3dStdZ is not None else 0,
                entry.rawMagnet3dRoXy if entry.rawMagnet3dRoXy is not None else 0,
                entry.rawMagnet3dRoXz if entry.rawMagnet3dRoXz is not None else 0,
                entry.rawMagnet3dRoYz if entry.rawMagnet3dRoYz is not None else 0,
                entry.locationNumValidUpdates if entry.locationNumValidUpdates is not None else 0,
                entry.locationLogLatitudeRange if entry.locationLogLatitudeRange is not None else 0,
                entry.locationLogLongitudeRange if entry.locationLogLongitudeRange is not None else 0,
                entry.locationMinAltitude if entry.locationMinAltitude is not None else 0,
                entry.locationMaxAltitude if entry.locationMaxAltitude is not None else 0,
                entry.locationMinSpeed if entry.locationMinSpeed is not None else 0,
                entry.locationMaxSpeed if entry.locationMaxSpeed is not None else 0,
                entry.locationBestHorizontalAccuracy if entry.locationBestHorizontalAccuracy is not None else 0,
                entry.locationBestVerticalAccuracy if entry.locationBestVerticalAccuracy is not None else 0,
                entry.locationDiameter if entry.locationDiameter is not None else 0,
                entry.locationLogDiameter if entry.locationLogDiameter is not None else 0,
                entry.locationQuickFeaturesStdLat if entry.locationQuickFeaturesStdLat is not None else 0,
                entry.locationQuickFeaturesStdLong if entry.locationQuickFeaturesStdLong is not None else 0,
                entry.locationQuickFeaturesLatChange if entry.locationQuickFeaturesLatChange is not None else 0,
                entry.locationQuickFeaturesLongChange if entry.locationQuickFeaturesLongChange is not None else 0,
                entry.audioNaiveMfcc0Mean if entry.audioNaiveMfcc0Mean is not None else 0,
                entry.audioNaiveMfcc1Mean if entry.audioNaiveMfcc1Mean is not None else 0,
                entry.audioNaiveMfcc2Mean if entry.audioNaiveMfcc2Mean is not None else 0,
                entry.audioNaiveMfcc3Mean if entry.audioNaiveMfcc3Mean is not None else 0,
                entry.audioNaiveMfcc4Mean if entry.audioNaiveMfcc4Mean is not None else 0,
                entry.audioNaiveMfcc5Mean if entry.audioNaiveMfcc5Mean is not None else 0,
                entry.audioNaiveMfcc6Mean if entry.audioNaiveMfcc6Mean is not None else 0,
                entry.audioNaiveMfcc7Mean if entry.audioNaiveMfcc7Mean is not None else 0,
                entry.audioNaiveMfcc8Mean if entry.audioNaiveMfcc8Mean is not None else 0,
                entry.audioNaiveMfcc9Mean if entry.audioNaiveMfcc9Mean is not None else 0,
                entry.audioNaiveMfcc10Mean if entry.audioNaiveMfcc10Mean is not None else 0,
                entry.audioNaiveMfcc11Mean if entry.audioNaiveMfcc11Mean is not None else 0,
                entry.audioNaiveMfcc12Mean if entry.audioNaiveMfcc12Mean is not None else 0,
                entry.audioNaiveMfcc0Std if entry.audioNaiveMfcc0Std is not None else 0,
                entry.audioNaiveMfcc1Std if entry.audioNaiveMfcc1Std is not None else 0,
                entry.audioNaiveMfcc2Std if entry.audioNaiveMfcc2Std is not None else 0,
                entry.audioNaiveMfcc3Std if entry.audioNaiveMfcc3Std is not None else 0,
                entry.audioNaiveMfcc4Std if entry.audioNaiveMfcc4Std is not None else 0,
                entry.audioNaiveMfcc5Std if entry.audioNaiveMfcc5Std is not None else 0,
                entry.audioNaiveMfcc6Std if entry.audioNaiveMfcc6Std is not None else 0,
                entry.audioNaiveMfcc7Std if entry.audioNaiveMfcc7Std is not None else 0,
                entry.audioNaiveMfcc8Std if entry.audioNaiveMfcc8Std is not None else 0,
                entry.audioNaiveMfcc9Std if entry.audioNaiveMfcc9Std is not None else 0,
                entry.audioNaiveMfcc10Std if entry.audioNaiveMfcc10Std is not None else 0,
                entry.audioNaiveMfcc11Std if entry.audioNaiveMfcc11Std is not None else 0,
                entry.audioNaiveMfcc12Std if entry.audioNaiveMfcc12Std is not None else 0,
                entry.audioPropertiesMaxAbsValue if entry.audioPropertiesMaxAbsValue is not None else 0,
                entry.audioPropertiesNormalizationMultiplier if entry.audioPropertiesNormalizationMultiplier is not None else 0,


                # Convert boolean values to integers (True=1, False=0)
                int(entry.discreteAppStateIsActive if entry.discreteAppStateIsActive is not None else 0),
                int(entry.discreteAppStateIsInactive if entry.discreteAppStateIsInactive is not None else 0),
                int(entry.discreteAppStateIsBackground if entry.discreteAppStateIsBackground is not None else 0),
                int(entry.discreteAppStateMissing if entry.discreteAppStateMissing is not None else 0),
                int(entry.discreteBatteryPluggedIsAc if entry.discreteBatteryPluggedIsAc is not None else 0),
                int(entry.discreteBatteryPluggedIsUsb if entry.discreteBatteryPluggedIsUsb is not None else 0),
                int(entry.discreteBatteryPluggedIsWireless if entry.discreteBatteryPluggedIsWireless is not None else 0),
                int(entry.discreteBatteryPluggedMissing if entry.discreteBatteryPluggedMissing is not None else 0),
                int(entry.discreteBatteryStateIsUnknown if entry.discreteBatteryStateIsUnknown is not None else 0),
                int(entry.discreteBatteryStateIsUnplugged if entry.discreteBatteryStateIsUnplugged is not None else 0),
                int(entry.discreteBatteryStateIsNotCharging if entry.discreteBatteryStateIsNotCharging is not None else 0),
                int(entry.discreteBatteryStateIsDischarging if entry.discreteBatteryStateIsDischarging is not None else 0),
                int(entry.discreteBatteryStateIsCharging if entry.discreteBatteryStateIsCharging is not None else 0),
                int(entry.discreteBatteryStateIsFull if entry.discreteBatteryStateIsFull is not None else 0),
                int(entry.discreteBatteryStateMissing if entry.discreteBatteryStateMissing is not None else 0),
                int(entry.discreteOnThePhoneIsFalse if entry.discreteOnThePhoneIsFalse is not None else 0),
                int(entry.discreteOnThePhoneIsTrue if entry.discreteOnThePhoneIsTrue is not None else 0),
                int(entry.discreteOnThePhoneMissing if entry.discreteOnThePhoneMissing is not None else 0),
                int(entry.discreteRingerModeIsNormal if entry.discreteRingerModeIsNormal is not None else 0),
                int(entry.discreteRingerModeIsSilentNoVibrate if entry.discreteRingerModeIsSilentNoVibrate is not None else 0),
                int(entry.discreteRingerModeIsSilentWithVibrate if entry.discreteRingerModeIsSilentWithVibrate is not None else 0),
                int(entry.discreteRingerModeMissing if entry.discreteRingerModeMissing is not None else 0),
                int(entry.discreteWifiStatusIsNotReachable if entry.discreteWifiStatusIsNotReachable is not None else 0),
                int(entry.discreteWifiStatusIsReachableViaWifi if entry.discreteWifiStatusIsReachableViaWifi is not None else 0),
                int(entry.discreteWifiStatusIsReachableViaWwan if entry.discreteWifiStatusIsReachableViaWwan is not None else 0),
                int(entry.discreteWifiStatusMissing if entry.discreteWifiStatusMissing is not None else 0),
                int(entry.discreteTimeOfDayBetween0and6 if entry.discreteTimeOfDayBetween0and6 is not None else 0),
                int(entry.discreteTimeOfDayBetween3and9 if entry.discreteTimeOfDayBetween3and9 is not None else 0),
                int(entry.discreteTimeOfDayBetween6and12 if entry.discreteTimeOfDayBetween6and12 is not None else 0),
                int(entry.discreteTimeOfDayBetween9and15 if entry.discreteTimeOfDayBetween9and15 is not None else 0),
                int(entry.discreteTimeOfDayBetween12and18 if entry.discreteTimeOfDayBetween12and18 is not None else 0),
                int(entry.discreteTimeOfDayBetween15and21 if entry.discreteTimeOfDayBetween15and21 is not None else 0),
                int(entry.discreteTimeOfDayBetween18and24 if entry.discreteTimeOfDayBetween18and24 is not None else 0),
                int(entry.discreteTimeOfDayBetween21and3 if entry.discreteTimeOfDayBetween21and3 is not None else 0),

                # Low-frequency measurements
                entry.lfMeasurementsLight if entry.lfMeasurementsLight is not None else 0,
                entry.lfMeasurementsPressure if entry.lfMeasurementsPressure is not None else 0,
                entry.lfMeasurementsProximityCm if entry.lfMeasurementsProximityCm is not None else 0,
                entry.lfMeasurementsProximity if entry.lfMeasurementsProximity is not None else 0,
                entry.lfMeasurementsRelativeHumidity if entry.lfMeasurementsRelativeHumidity is not None else 0,
                entry.lfMeasurementsBatteryLevel if entry.lfMeasurementsBatteryLevel is not None else 0,
                entry.lfMeasurementsScreenBrightness if entry.lfMeasurementsScreenBrightness is not None else 0,
                1 if entry.activityType == "IN_VEHICLE" else 0,
                1 if entry.activityType == "WALKING" else 0,
                1 if entry.activityType == "RUNNING" else 0,
                1 if entry.activityType == "ON_BICYCLE" else 0,
                1 if entry.activityType == "SLEEPING" else 0
            ]
            print(feature_values)
            features.append(feature_values)

        # Convert the list of feature values into a NumPy array
        input_data = np.array(features)

        # Validate input shape
        if len(input_data.shape) != 2:
            raise HTTPException(status_code=400, detail="Input data must be 2D (batch_size x features).")

        print(input_data.shape)

        # Reshape for LSTM (batch_size, time_steps, features)
        input_data = input_data.reshape((input_data.shape[0], 1, input_data.shape[1]))

        # Run the prediction
        predictions = model.predict(input_data)

        # Example: Assuming you know the label names
        label_names = [
            "TALKING",
            "WITH_FRIENDS",
            "EATING",
            "WATCHING_TV",
            "IN_CLASS",
            "IN_A_MEETING",
            "COOKING",
            "CLEANING",
            "TOILET",
            "FIX_restaurant",
            "SHOPPING",
            "WASHING_DISHES",
            "AT_THE_GYM",
            "DOING_LAUNDRY",
            "ELEVATOR"
        ]

        # Assign labels to each prediction
        predicted_labels = [label_names[np.argmax(pred)] for pred in predictions]

        # Output
        print(predicted_labels)
        for pred in predictions:
            print(pred)
            print(np.sum(pred))

        # Format the predictions
        return {"prediction": most_frequent(predicted_labels)}

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error during prediction: {e}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

