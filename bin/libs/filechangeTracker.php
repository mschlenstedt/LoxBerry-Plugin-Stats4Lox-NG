<?php
/*
	PHP File Change Tracker class based on file modification time
	2021 Christian Fenzl
	Apache 2.0 License
	http://github.com/christianTF/PHP-Filechange-Tracker
*/

class filechangeTracker
{
	private $files;
	private $changedcounter = 0;
	
	public function __construct()
	{
		$this->files = array();
	}

	public function addmonitor( $filename, $functionToCall ) {
		$this->files[$filename]["filename"] = $filename;
		$this->files[$filename]["mtime"] = false;
		$this->files[$filename]["function"] = $functionToCall;
		
		if( !is_callable( $functionToCall, false, $callable ) ) {
			throw new Exception("$functionToCall is not callable. Misstyped?\n");
		}
		
	}

	public function removemonitor( $filename ) {
		unset( $this->files[$filename] );
	}
	
	public function dump() {
		print_r($this->files);
	}
	
	public function check() {
		$changedcounter = 0;
		foreach( $this->files as $filename => $filedata ) {
			clearstatcache(true, $filename);
			$newfilemtime = @filemtime( $filename );
			if( $newfilemtime != $this->files[$filename]["mtime"] ) {
				$this->files[$filename]["mtime"] = $newfilemtime;
				$changedcounter++;
				
				// Call function
				call_user_func( $filedata["function"], $filename, $newfilemtime );
				
			}
		}
		return $changedcounter;
	}
}
