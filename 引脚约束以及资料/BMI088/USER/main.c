#include "sys.h"
#include "delay.h"
#include "usart.h"
#include "bmi088_mm.h"
#include <math.h>
#include "common.h"



// VCC--------5V或者3.3V都可以
// SPI 模式接线
// PA2 ------------------------CS0
// PA4 ------------------------CS1
// PA5 ------------------------SCLK
// PA6------------------------MISO
// PA7------------------------MOSI

// IIC 接线
// PC1 ------------------------SCL
// PC2 ------------------------SDA
/* Interface reference is given as a parameter
     * For I2C : BMI2_I2C_INTF
     * For SPI : BMI2_SPI_INTF
     */
/*! Earth's gravity in m/s^2 */
#define GRAVITY_EARTH  (9.80665f)

/*********************************************************************/
/*                        Global variables                           */
/*********************************************************************/

struct bmi08_sensor_data bmi08_accel;

struct bmi08_sensor_data bmi08_gyro;

/*********************************************************************/
/*                       Function Declarations                       */
/*********************************************************************/

/*!
 * @brief This internal API is used to initialize the bmi08 sensor
 */
static void init_bmi08(struct bmi08_dev *bmi08dev);

/*!
 * @brief This internal API is used to configure accel and gyro data ready interrupts
 */
static void configure_accel_gyro_data_ready_interrupts(struct bmi08_dev *bmi08dev);

/*!
 *  @brief This function converts lsb to meter per second squared for 16 bit accelerometer at
 *  range 2G, 4G, 8G or 16G.
 *
 *  @param[in] val       : LSB from each axis.
 *  @param[in] g_range   : Gravity range.
 *  @param[in] bit_width : Resolution for accel.
 *
 *  @return Value in Meter Per second squared.
 */
static float lsb_to_mps2(int16_t val, float g_range, uint8_t bit_width);

/*!
 *  @brief This function converts lsb to degree per second for 16 bit gyro at
 *  range 125, 250, 500, 1000 or 2000dps.
 *
 *  @param[in] val       : LSB from each axis.
 *  @param[in] dps       : Degree per second.
 *  @param[in] bit_width : Resolution for gyro.
 *
 *  @return Value in Degree Per Second.
 */
static float lsb_to_dps(int16_t val, float dps, uint8_t bit_width);

/*********************************************************************/
/*                          Functions                                */
/*********************************************************************/

/*!
 *  @brief This internal API is used to initializes the bmi08 sensor
 *
 *  @param[in] void
 *
 *  @return void
 *
 */
static void init_bmi08(struct bmi08_dev *bmi08dev)
{
    int8_t rslt;

    /* Initialize bmi08 sensors (accel & gyro) */
    if (bmi088_mma_init(bmi08dev) == BMI08_OK && bmi08g_init(bmi08dev) == BMI08_OK)
    {
        printf("BMI08 initialization success!\n");
        printf("Accel chip ID - 0x%x\n", bmi08dev->accel_chip_id);
        printf("Gyro chip ID - 0x%x\n", bmi08dev->gyro_chip_id);

        /* Reset the accelerometer */
        rslt = bmi08a_soft_reset(bmi08dev);
    }
    else
    {
        printf("BMI08 initialization failure!\n");
        return;
    }

    if (rslt == BMI08_OK)
    {
        /* Set accel power mode */
        bmi08dev->accel_cfg.power = BMI08_ACCEL_PM_ACTIVE;
        rslt = bmi08a_set_power_mode(bmi08dev);
    }

    if (rslt == BMI08_OK)
    {
        bmi08dev->gyro_cfg.power = BMI08_GYRO_PM_NORMAL;
        rslt = bmi08g_set_power_mode(bmi08dev);
    }

    if (rslt == BMI08_OK)
    {
        bmi08dev->accel_cfg.odr = BMI08_ACCEL_ODR_100_HZ;
        bmi08dev->accel_cfg.range = BMI088_MM_ACCEL_RANGE_6G;

        bmi08dev->accel_cfg.power = BMI08_ACCEL_PM_ACTIVE;
        bmi08dev->accel_cfg.bw = BMI08_ACCEL_BW_NORMAL; /* Bandwidth and OSR are same */

        rslt = bmi08a_set_power_mode(bmi08dev);

        if (rslt == BMI08_OK)
        {
            rslt = bmi088_mma_set_meas_conf(bmi08dev);
            bmi08_check_rslt("bmi088_mma_set_meas_conf", rslt);

            bmi08dev->gyro_cfg.odr = BMI08_GYRO_BW_32_ODR_100_HZ;
            bmi08dev->gyro_cfg.range = BMI08_GYRO_RANGE_1000_DPS;
            bmi08dev->gyro_cfg.bw = BMI08_GYRO_BW_32_ODR_100_HZ;
            bmi08dev->gyro_cfg.power = BMI08_GYRO_PM_NORMAL;

            rslt = bmi08g_set_power_mode(bmi08dev);

            if (rslt == BMI08_OK)
            {
                rslt = bmi08g_set_meas_conf(bmi08dev);
                bmi08_check_rslt("bmi08g_set_meas_conf", rslt);
            }
        }
    }
}

static void configure_accel_gyro_data_ready_interrupts(struct bmi08_dev *bmi08dev)
{
    int8_t rslt;
    struct bmi08_accel_int_channel_cfg accel_int_config;
    struct bmi08_gyro_int_channel_cfg gyro_int_config;

    /* Configure the Interrupt configurations for accel */
    accel_int_config.int_channel = BMI08_INT_CHANNEL_1;
    accel_int_config.int_type = BMI08_ACCEL_INT_DATA_RDY;
    accel_int_config.int_pin_cfg.lvl = BMI08_INT_ACTIVE_HIGH;
    accel_int_config.int_pin_cfg.output_mode = BMI08_INT_MODE_PUSH_PULL;
    accel_int_config.int_pin_cfg.enable_int_pin = BMI08_ENABLE;

    /* Set the interrupt configuration */
    rslt = bmi088_mma_set_int_config(&accel_int_config, BMI088_MM_ACCEL_DATA_RDY_INT, bmi08dev);

    if (rslt == BMI08_OK)
    {
        /* Configure the Interrupt configurations for gyro */
        gyro_int_config.int_channel = BMI08_INT_CHANNEL_3;
        gyro_int_config.int_type = BMI08_GYRO_INT_DATA_RDY;
        gyro_int_config.int_pin_cfg.enable_int_pin = BMI08_ENABLE;
        gyro_int_config.int_pin_cfg.lvl = BMI08_INT_ACTIVE_HIGH;
        gyro_int_config.int_pin_cfg.output_mode = BMI08_INT_MODE_PUSH_PULL;

        rslt = bmi08g_set_int_config(&gyro_int_config, bmi08dev);
    }

    if (rslt != BMI08_OK)
    {
        printf("Failure in interrupt configurations \n");
        return;
    }
}

/*!
 * @brief This function converts lsb to meter per second squared for 16 bit accelerometer at
 * range 2G, 4G, 8G or 16G.
 */
static float lsb_to_mps2(int16_t val, float g_range, uint8_t bit_width)
{
    double power = 2;

    float half_scale = (float)((pow((double)power, (double)bit_width) / 2.0f));

    return (GRAVITY_EARTH * val * g_range) / half_scale;
}

/*!
 * @brief This function converts lsb to degree per second for 16 bit gyro at
 * range 125, 250, 500, 1000 or 2000dps.
 */
static float lsb_to_dps(int16_t val, float dps, uint8_t bit_width)
{
    double power = 2;

    float half_scale = (float)((pow((double)power, (double)bit_width) / 2.0f));

    return (dps / (half_scale)) * (val);
}


int main(void)
{
    int8_t rslt;
    struct bmi08_dev bmi08;
    uint8_t status = 0;
//    uint8_t times_to_read = 0;
    float x, y, z;
	
    HAL_Init();                   	//初始化HAL库    
    Stm32_Clock_Init(336,8,2,7);  	//设置时钟,168Mhz
	delay_init(168);               	//初始化延时函数
	uart_init(115200);             	//初始化USART
	
    /* Interface reference is given as a parameter
     *         For I2C : BMI08_I2C_INTF
     *         For SPI : BMI08_SPI_INTF
     */
    rslt = bmi08_interface_init(&bmi08, BMI08_SPI_INTF);
    //rslt = bmi08_interface_init(&bmi08, BMI08_I2C_INTF);	
	//IMU_INIT_GETDATA();
	/* Initialize the sensors */
    init_bmi08(&bmi08);

    configure_accel_gyro_data_ready_interrupts(&bmi08);

    for (;;)
    {
        /* Read accel data ready interrupt status */
//        rslt = bmi08a_get_data_int_status(&status, &bmi08);
//        bmi08_check_rslt("bmi08a_get_data_int_status", rslt);
//        //printf("acc status = %d\n", status);
//        if ((status & BMI08_ACCEL_DATA_READY_INT))
//        {
            rslt = bmi088_mma_get_data(&bmi08_accel, &bmi08);
            bmi08_check_rslt("bmi088_mma_get_data", rslt);


//            printf("\nAcc_X = %d\t", bmi08_accel.x);
//            printf("Acc_Y = %d\t", bmi08_accel.y);
//            printf("Acc_Z = %d", bmi08_accel.z);

            /* Converting lsb to meter per second squared for 16 bit accelerometer at 3G range. */
            x = lsb_to_mps2(bmi08_accel.x, (float)6, 16);
            y = lsb_to_mps2(bmi08_accel.y, (float)6, 16);
            z = lsb_to_mps2(bmi08_accel.z, (float)6, 16);

            /* Print the data in m/s2. */
            printf("Acc_ms2_X = %4.2f, Acc_ms2_Y = %4.2f, Acc_ms2_Z = %4.2f\t", x, y, z);

//        }

        /* Read gyro data ready interrupt status */
//        rslt = bmi08g_get_data_int_status(&status, &bmi08);
//        bmi08_check_rslt("bmi08g_get_data_int_status", rslt);
//        //printf("gyro status = %d\n", status);

//        if ((status & BMI08_GYRO_DATA_READY_INT))
//        {
            rslt = bmi08g_get_data(&bmi08_gyro, &bmi08);
            bmi08_check_rslt("bmi08g_get_data", rslt);


//            printf("\nGyr_X = %d\t", bmi08_gyro.x);
//            printf("Gyr_Y = %d\t", bmi08_gyro.y);
//            printf("Gyr_Z = %d\n", bmi08_gyro.z);

            /* Converting lsb to degree per second for 16 bit gyro at 2000dps range. */
            x = lsb_to_dps(bmi08_gyro.x, (float)1000, 16);
            y = lsb_to_dps(bmi08_gyro.y, (float)1000, 16);
            z = lsb_to_dps(bmi08_gyro.z, (float)1000, 16);

            /* Print the data in dps. */
            printf("Gyro_DPS_X = %4.2f,\tGyro_DPS_Y = %4.2f,\tGyro_DPS_Z = %4.2f\n", x, y, z);

//        }

        delay_ms(10);
    }

    bmi08_coines_deinit();

    return rslt;
}

