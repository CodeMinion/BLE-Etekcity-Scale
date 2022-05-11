# Sample Flutter App Connecting to an EtekCity Scale

Connects to an Etekcity and displays the scale's reading on the screen. 

This particular model (https://www.amazon.com/gp/product/B095YJW56C/ref=ox_sc_act_title_1?smid=ATVPDKIKX0DER&th=1) 
includes the scale measurements under a GATT service of 0xFFF0 and the weight measurements 
in the 0xFFF1 characteristic in that service. From the value in that characteristic we 
take bytes 10 and 11 (little endian) and convert it to pounds. 

