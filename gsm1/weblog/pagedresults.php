<?php
# Copyright By Kevin Yank

class MySQLPagedResultSet
{

  var $results;
  var $pageSize;
  var $page;
  var $row;
  
  function MySQLPagedResultSet($query,$pageSize,$cnx)
  {
    $resultpage = $_GET['resultpage'];
    
    $this->results = @mysql_query($query,$cnx);
    $this->pageSize = $pageSize;
    if ((int)$resultpage <= 0) $resultpage = 1;
    if ($resultpage > $this->getNumPages())
      $resultpage = $this->getNumPages();
    $this->setPageNum($resultpage);
  }
  
  function getNumPages()
  {
    if (!$this->results) return FALSE;
    
    return ceil(mysql_num_rows($this->results) /
                (float)$this->pageSize);
  }
  
  function setPageNum($pageNum)
  {
    if ($pageNum > $this->getNumPages() or
        $pageNum <= 0) return FALSE;
  
    $this->page = $pageNum;
    $this->row = 0;
    mysql_data_seek($this->results,($pageNum-1) * $this->pageSize);
  }
  
  function getPageNum()
  {
    return $this->page;
  }
  
  function isLastPage()
  {
    return ($this->page >= $this->getNumPages());
  }
  
  function isFirstPage()
  {
    return ($this->page <= 1);
  }
  
  function fetchArray()
  {
    if (!$this->results) return FALSE;
    if ($this->row >= $this->pageSize) return FALSE;
    $this->row++;
    return mysql_fetch_array($this->results);
  }
  
  function getPageNav($queryvars = '')
  {
    $nav = '';
    if (!$this->isFirstPage())
    {
      $nav .= "<a href=\"?resultpage=".
              ($this->getPageNum()-1).'&'.$queryvars.'">Prev</a> ';
    }
    if ($this->getNumPages() > 1)
      for ($i=1; $i<=$this->getNumPages(); $i++)
      {
        if ($i==$this->page)
          $nav .= "$i ";
        else
          $nav .= "<a href=\"?resultpage={$i}&".
                  $queryvars."\">{$i}</a> ";
      }
    if (!$this->isLastPage())
    {
      $nav .= "<a href=\"?resultpage=".
              ($this->getPageNum()+1).'&'.$queryvars.'">Next</a> ';
    }
    
    return $nav;
  }
}

?>
