
<?php

// 禁止错误显示
error_reporting(0);

class Sample {

    public static function testPhp() {
        $displayInfo = "Test PHP Page...";
        echo $displayInfo . PHP_EOL;
    }

    public static function testRedis() {
        $redis = new Redis();
        try {
            $redis->connect('redis', 6379);
            $redis->auth('ENV_REDIS_PASSWORD');
            $value = $redis->set('foo', rand(1, 1000000));
            $response = $redis->get('foo');
            echo "Test Redis (random value): $response  OK." . PHP_EOL;
        } catch (Exception $e) {
            echo "Redis error: " . $e->getMessage() . PHP_EOL;
        }
    }

    public static function testMysql(){
        $username = "ENV_MYSQL_USER";
        $passwd = "ENV_MYSQL_PASSWORD";
        $arr_dns = array("mysql");
        // PHP 7.4 以上支持 MySQL 8.*，否则不支持
        foreach ($arr_dns as $dns) {
            $connection = mysqli_init();
            $connection->options(MYSQLI_OPT_CONNECT_TIMEOUT, 5);
            $connection->options(MYSQLI_OPT_READ_TIMEOUT, 5);
            // $connection = mysqli_connect($dns,$username,$passwd);
            if(mysqli_real_connect($connection,$dns,$username,$passwd)){
                echo "Test MySQL connect:    OK." . PHP_EOL;
            } else {
                // die("connection Failed:" . mysqli_connect_errno());
                echo "Test MySQL connect:    Fail." . PHP_EOL;
            }
            mysqli_close($connection);
        }
    }

    public static function main() {
        self::testPhp();
        self::testRedis();
        self::testMysql();
    }
}

Sample::main();

