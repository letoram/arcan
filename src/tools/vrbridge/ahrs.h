/*
 * Madgwick AHRS
 * License (GPLv2)
 * Reference: http://www.x-io.co.uk/node/8#open_source_ahrs_and_imu_algorithms
 */

/*
 * An interesting exploration here would be to use the skeleton model from the
 * vr- structure where the mapped joints will have a sensor each, and to feed
 * this into a Kalman filter that uses a human- tuned inverse-kinematics model
 * for prediction
 */
struct ahrs_context {
	quat rot_quat;
	float beta;
	float rate;
	float q0, q1, q2, q3;
};

void AHRS_init(struct ahrs_context*, float samplerate);

/*
 * Only update if all three sets have been sampled in the same timeframe
 */
void AHRS_update(struct ahrs_context*,
	float gyro[3], float accel[3], float magnet[3]);

/*
 * Convert the internal ahrs- context to an orientation quaternion suitable for
 * openGL- use
 */
void AHRS_sample(struct ahrs_context*, quat* dst);
