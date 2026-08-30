<?php

include_once("../db.php");

date_default_timezone_set("Asia/Tashkent");

$soat = date('H:i');
$sana = date('d.m.Y');


function bot($method,$datas=[]){
    $url = "https://api.telegram.org/bot6234100789:AAEX32FWFsQEhqBYYZU-fIBe00WgOg0KUyY/".$method;
    $ch = curl_init();
    curl_setopt($ch,CURLOPT_URL,$url);
    curl_setopt($ch,CURLOPT_RETURNTRANSFER,true);
    curl_setopt($ch,CURLOPT_POSTFIELDS,$datas);
    $res = curl_exec($ch);
    if(curl_error($ch)){
        var_dump(curl_error($ch));
    }else{
        return json_decode($res);
    }
}
 
 

header("Content-Type: application/json; charset=UTF-8");

if(isset($_POST)){

if($_POST['error'] == "0"){

    $chat_id = $_POST['merchant_trans_id'];
    $amount = $_POST['amount'];

    $time = time();
    mysqli_query($db,"INSERT INTO `transaction` (`id`, `chat_id`, `amount`, `created_date`, `status`) VALUES (NULL, '$chat_id', '$amount', '$time', '1')");
        
        $res = mysqli_query($db, "SELECT * FROM `users` WHERE `chat_id` = '$chat_id'"); 
    $a = mysqli_fetch_assoc($res);
    $balance = $a['pul'];

    $addmoney = $balance + ($amount * 2);
        
        bot('SendMessage',[
        'chat_id'=>"499816482",
        'text'=>"<b>➕ Hisobi to'ldirildi. 
💵 To'lov turi: 🔹 Click ( Avto )

🔢 Miqdori: $amount so'm [X2]
👉 Foydalanuvchi: <a href='tg://user?id=$chat_id'>$chat_id</a> 
🗃 Hozirda hisobi: $addmoney so'm</b>",
        'disable_web_page_preview'=>true,
        'parse_mode'=>'html',
    ]);
        
    mysqli_query($db,"UPDATE `users` SET `pul` = $addmoney WHERE `chat_id` = '$chat_id'");

    $aamount = $amount * 2;

    bot('sendMessage',[
        'chat_id'=>$chat_id,
        'text'=>"<b>💵 Hisobingizga $amount so'm qo'shildi</b>\n\n🔥 Biz sizga + $amount so'm bonus berdik va jami: $aamount so'm bo'ldi",
        'parse_mode'=>'html'
    ]);
    

    $r = $_POST;

    $res = [
        "click_trans_id"=>(int)$r["click_trans_id"],
        "merchant_trans_id"=>(int)$r["merchant_trans_id"],
        "merchant_confirm_id"=>(int)rand(34,3828),
        "error"=>0,
        "error_note"=>"Success",
    ];

    echo json_encode($res,JSON_PRETTY_PRINT);


    if(isset($_POST['merchant_trans_id'])){ 
        try{
            $m = $_POST['merchant_trans_id'];
            $p = json_encode($_POST);
            $t = time();
            mysqli_query($db,"INSERT INTO `transaction_log` (`id`,`type`, `merchant_trans_id`, `logs`, `created_date`, `status`) VALUES (NULL,'complete', '$m', '$p', '$t', '1')");
        }
        catch(Exception $e){
            // echo $e->getMessage();
        }
    }
}
}