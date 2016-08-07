<?php

print_r(getallheaders());

print_r($_POST);
print_r($_FILES);
print_r($_GLOBAL);

?>

<html><body>
<form method="post" enctype="multipart/form-data">

<input type="file" name="example" size="30">
<input type="text" name="ex2" size="30">
<input type="submit" value="Send" />

</form>

</body></html>

