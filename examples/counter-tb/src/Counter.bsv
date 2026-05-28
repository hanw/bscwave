// Counter.bsv
interface Counter;
  method Action clear;
  method Action incr;
  method Bit#(8) dout;
endinterface

module mkCounter(Counter);
  Reg#(Bit#(8)) count <- mkReg(0);
  method Action clear; count <= 0; endmethod
  method Action incr;  count <= count + 1; endmethod
  method Bit#(8) dout; return count; endmethod
endmodule

