<?php
include_once("../db.php");

date_default_timezone_set("Asia/Tashkent");
header("Content-Type:application/json");


$r = $_POST;
$res = [ 
    "click_trans_id"=>(int)$r['click_trans_id'], 
    "merchant_trans_id"=>(int)$r['merchant_trans_id'],
    "error"=>0,
    "error_note"=>"Success",
    "merchant_prepare_id"=>(int)rand(34,3828)
];

echo json_encode($res,JSON_PRETTY_PRINT);

if(isset($_POST['merchant_trans_id'])){
    try{
        $m = $_POST['merchant_trans_id'];
        $p = json_encode($_POST);
        $t = time();
        mysqli_query($db,"INSERT INTO `transaction_log` (`id`,`type`, `merchant_trans_id`, `logs`, `created_date`, `status`) VALUES (NULL,'prepare', '$m', '$p', '$t', '1')");
    }
    catch(Exception $e){
        // echo $e->getMessage();
    }
}

?>