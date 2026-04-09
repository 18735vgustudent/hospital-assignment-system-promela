#define TIME_LIMIT 480
#define N_SUBJECTS 20
#define N_CUSTOMER_MAX 200

#define N_OPERATING_ROOM 2


mtype:messageType = { SUB, UNSUB, TICK, ACK };
mtype:customerType = { NORM, INS, VIP };
mtype:department = { A, B, C };


typedef Customer {
    byte id;
    mtype:customerType type;
    mtype:department dept;
}

typedef WalkingCustomer {
    Customer customer;
    byte minuteLeft;
}

byte customerUniversalId = 0;

int globalTime = 0;

bool isClosed = false;


// Channel to send SUB/UNSUB request (along with _pid).
chan timeRegistration = [N_SUBJECTS] of { mtype:messageType, byte };

// Channel(s) to send TICK/ACK.
chan timeNotify[N_SUBJECTS] = [1] of { mtype:messageType };
chan timeReply[N_SUBJECTS] = [0] of { mtype:messageType };

chan customerEntrance = [3] of { Customer };
chan customerHallway = [20] of { Customer };


/* --- DEPARTMENT A DEFINITIONS --- */
// 3 Doctors, 2 Machines. Treatment 10-20 mins (avg 15).
// 2 Machines handling 15 min avg = 7.5 min effective throughput.
#define avgTreatmentTime_DeptA 8 

chan deptQueue_A_VIP = [20] of { byte };
chan deptQueue_A_INS = [20] of { byte };
chan deptQueue_A_NORM = [20] of { byte };

byte nWaitingCustomer_DeptA = 0;
bool isClosed_DeptA = false;

// Resource Management for Dept A
byte freeMachines_DeptA = 2;     // Total Physical Machines
byte reservedMachines_DeptA = 0; // Machines reserved by incoming VIPs (Phantom Congestion)
byte doctorUniversalId_A;

/* --- END DEPARTMENT A DEFINITIONS --- */


// Dept B: Exam (4) + Treatment (12.5 to 17.5) ~ 20 (safe margin)
// 3 doctors => 20 / 3 ~~ 6
#define avgTreatmentTime_DeptB 6
/*
Department B Channels:
- Junior Queue High Priority (Insured)
- Junior Queue Low Priority (Normal)
- Senior Queue (VIP + Referrals)
*/
chan deptQueue_B_Junior_INS = [20] of { byte }; 
chan deptQueue_B_Junior_NORM = [20] of { byte };
chan deptQueue_B_Senior = [20] of { byte, mtype:customerType }; // ID, type

// Variables for Dept B rejection rule
byte nWaitingCustomer_DeptB = 0;
bool isClosed_DeptB = false;

byte juniorDoctorUniversalId = 0;


/*
Department C: 
- Time in Pre-OP Room [3-5]  
- Time in OP Room [20-30]
- Cleaning time [5-10] 
Minimum treatment time of department C: 3 + 20
Minimum cleaning time after each treatment: 5
There are 2 OP Room => Maximum 2 treatments at a time.
=> Maximum [ 480 / (3+20+5) ] x 2 = 32.28 clients per day
*/
// PreOP + OP + Cleaning | 2 operating rooms
// (4 + 25 + 7) / 2 = 36 / 2 = 18
#define avgTreatmentTime_DeptC 18

chan deptQueue_C = [20] of { byte, mtype:customerType };  // (customer id, customer type)
chan deptVIPQueue_C = [20] of { byte };  // (customer id)

mtype:opRoomState = { CLEAN, DIRTY, BUSY };

byte operatingRoomUniversalId = 0;
mtype:opRoomState opRoom[N_OPERATING_ROOM] = CLEAN;

byte preOPCustomerID = 0;
mtype:customerType preOPCustomerType;
bool isPreOPReady = false;

byte nWaitingCustomer_DeptC = 0;
bool isClosed_DeptC = false;


active proctype ClockTicking() {
    bool isSubscribed[N_SUBJECTS];
    mtype:messageType reqMsg;
    byte reqId;
    byte i;

    do 
        :: {
            // Check ALL pending registrations (SUB/UNSUB).
            do
                :: nempty(timeRegistration) -> {
                    timeRegistration ? reqMsg, reqId;
                    if
                        :: reqMsg == SUB -> isSubscribed[reqId] = true;
                        :: reqMsg == UNSUB -> isSubscribed[reqId] = false;
                    fi
                }
                :: empty(timeRegistration) -> break;
            od

            // Call subscribed subjects to perform their tasks.
            for (i : 0 .. N_SUBJECTS-1) {
                if
                    :: isSubscribed[i] -> timeNotify[i] ! TICK;
                    :: else -> skip;
                fi
            }

            // Wait for subscribed subjects to finish their tasks.
            for (i : 0 .. N_SUBJECTS-1) {
                if
                    :: isSubscribed[i] -> timeReply[i] ? ACK;
                    :: else -> skip;
                fi
            }

            // Increment the time.
            globalTime++;
            // printf("%d\n", globalTime);
            if
                :: globalTime == TIME_LIMIT -> isClosed = true;
                :: else -> skip;
            fi

            // Working over time: treatment takes longer than expected.
            if 
                :: isClosed && _nr_pr == 1 -> {  // Stop when it is the only process left.
                    break;
                }
                :: else -> skip;
            fi
        }
    od
}

/*
+ 40% new normal customer
+ 20% new insurance customer
+ 10% new VIP
+ 30% no new customer
*/
active[3] proctype CustomerEntranceQueue() {
    Customer newCustomer;
    bool isSkip;

    do
        :: isClosed -> break;
        :: !isClosed -> {
            isSkip = false;
            // Randomly select customer's type.
            if
                :: 1 -> newCustomer.type = NORM;
                :: 2 -> newCustomer.type = NORM;
                :: 3 -> newCustomer.type = NORM;
                :: 4 -> newCustomer.type = NORM;
                :: 5 -> newCustomer.type = INS;
                :: 6 -> newCustomer.type = INS;
                :: 7 -> newCustomer.type = VIP;
                :: 8 -> isSkip = true;
                :: 9 -> isSkip = true;
                :: 10 -> isSkip = true;
            fi

            if
                :: !isSkip -> {
                    // Get new customer id.
                    atomic {
                        if
                            :: customerUniversalId >= N_CUSTOMER_MAX -> {
                                break;
                            }
                            :: else -> skip;
                        fi

                        newCustomer.id = customerUniversalId;
                        customerUniversalId++;
                    }

                    // Randomly select customer's department.
                    if
                        :: 1 -> newCustomer.dept = A;
                        :: 2 -> newCustomer.dept = B;
                        :: 3 -> newCustomer.dept = C;
                    fi

                    mtype:customerType temp = newCustomer.type;
                    printf("\nCustomer Entrance Queue %d: created a customer with id %d, type %e\n", _pid, newCustomer.id, temp);

                    // Add new customer to the queue
                    customerEntrance ! newCustomer;
                }
                :: else -> skip;
            fi
        }
    od
}


active proctype GateKeeper() {
    byte processingTime;
    Customer processingCustomer;
    do
        :: {
            // Non-critical: Wait for the next customer.
            if
                :: customerEntrance ? processingCustomer -> skip;
                :: isClosed && empty(customerEntrance) -> break;  // CLOSED.
            fi

            // Checking customer takes randomly 1-5 minutes.
            select (processingTime: 1 .. 5);

            // Register to the ClockTicking.
            timeRegistration ! SUB, _pid;


            // Critical: checking customer's type & department.
            // (sync with Global Time)
            do
                :: timeNotify[_pid] ? TICK -> {
                    processingTime--;
                    
                    if
                        :: processingTime == 0 -> {
                            // Unregister to the ClockTicking.
                            timeRegistration ! UNSUB, _pid;
                            timeReply[_pid] ! ACK;

                            assert(nWaitingCustomer_DeptB + nWaitingCustomer_DeptC + nWaitingCustomer_DeptA <= N_CUSTOMER_MAX);

                            // Done checking => proceed to decide accept/reject.
                            if 
                                :: processingCustomer.dept == A -> {
                                    // Department A Admission
                                    if
                                        :: globalTime <= TIME_LIMIT - (nWaitingCustomer_DeptA + 1) * avgTreatmentTime_DeptA -> {
                                            
                                            // --- VIP RESERVATION LOGIC ---
                                            // VIPs reserve a machine the moment they enter (are accepted by GateKeeper).
                                            if
                                                :: processingCustomer.type == VIP -> {
                                                    atomic { reservedMachines_DeptA++; }
                                                    printf("\nA - VIP %d Reserved a machine remotely at %d. Reserved Count: %d\n", processingCustomer.id, globalTime, reservedMachines_DeptA);
                                                }
                                                :: else -> skip;
                                            fi
                                            // -----------------------------

                                            customerHallway ! processingCustomer;
                                            nWaitingCustomer_DeptA++;
                                        }
                                        :: else -> {
                                            isClosed_DeptA = true;
                                        }
                                    fi
                                }
                                :: processingCustomer.dept == B -> {
                                    // Department B Admission with Rejection Rule
                                    if
                                        :: globalTime <= TIME_LIMIT - (nWaitingCustomer_DeptB + 1) * avgTreatmentTime_DeptB -> {
                                            customerHallway ! processingCustomer;
                                            nWaitingCustomer_DeptB++;
                                        }
                                        :: else -> {
                                            isClosed_DeptB = true;
                                        }
                                    fi
                                }
                                :: processingCustomer.dept == C -> {  // Checking rejection for department C
                                    if
                                        :: globalTime <= TIME_LIMIT - (nWaitingCustomer_DeptC + 1) * avgTreatmentTime_DeptC -> {
                                            customerHallway ! processingCustomer;
                                            nWaitingCustomer_DeptC++;
                                        }
                                        :: else -> {  // Reject
                                            isClosed_DeptC = true;
                                        }
                                    fi
                                    skip;
                                }
                            fi


                            break;
                        }
                        :: else -> skip;
                    fi

                    timeReply[_pid] ! ACK;
                }
            od
        }
    od
}

// Always countdown for every minutes.
active proctype HallWay() {
    WalkingCustomer walkCus[N_CUSTOMER_MAX];
    byte index;
    int i, j;

    timeRegistration ! SUB, _pid;
    do
        :: timeNotify[_pid] ? TICK -> {
            // Adding new entered customers.
            do
                :: nempty(customerHallway) -> {
                    customerHallway ? walkCus[index].customer;

                    // Walking time is randomly 1-5 minutes long.
                    byte walkingTime;
                    select (walkingTime: 1 .. 5);
                    walkCus[index].minuteLeft = walkingTime;

                    index++;       

                    assert(index < N_CUSTOMER_MAX);
                }
                :: empty(customerHallway) -> break;
            od

            // Decrease minuteLeft for each walking customer.
            i = 0;
            do
                :: i >= index -> break;
                :: i < index -> {
                    walkCus[i].minuteLeft--;
                    if
                        :: walkCus[i].minuteLeft == 0 -> {
                            // walkCus[i] has done walking => move to Department Queue.
                            if
                                :: walkCus[i].customer.dept == A -> {
                                    if
                                        :: walkCus[i].customer.type == VIP -> deptQueue_A_VIP ! walkCus[i].customer.id;
                                        :: walkCus[i].customer.type == INS -> deptQueue_A_INS ! walkCus[i].customer.id;
                                        :: walkCus[i].customer.type == NORM -> deptQueue_A_NORM ! walkCus[i].customer.id;
                                    fi
                                }
                                :: walkCus[i].customer.dept == B -> {
                                    if
                                        :: walkCus[i].customer.type == VIP -> {
                                            // VIP goes directly to Senior
                                            deptQueue_B_Senior ! walkCus[i].customer.id, VIP;
                                        }
                                        :: walkCus[i].customer.type == INS -> {
                                            // Insured goes to High Priority Junior Queue
                                            deptQueue_B_Junior_INS ! walkCus[i].customer.id;
                                        }
                                        :: else -> { 
                                            // Normal goes to Low Priority Junior Queue
                                            deptQueue_B_Junior_NORM ! walkCus[i].customer.id;
                                        }
                                    fi
                                }
                                :: walkCus[i].customer.dept == C -> {
                                    if
                                        :: walkCus[i].customer.type == VIP -> {
                                            deptVIPQueue_C ! walkCus[i].customer.id;
                                        }
                                        :: else -> {  // INS + NORM
                                            byte tempId = walkCus[i].customer.id;
                                            mtype:customerType tempType = walkCus[i].customer.type;
                                            deptQueue_C ! tempId, tempType;
                                        }
                                    fi
                                    skip;
                                }
                            fi  


                            if
                                :: index > 1 -> {
                                    // Remove walkCus[i] from the array (shifting to left).
                                    for (j : i .. index-2) {
                                        walkCus[j].customer.id = walkCus[j + 1].customer.id;
                                        walkCus[j].customer.type = walkCus[j + 1].customer.type;
                                        walkCus[j].customer.dept = walkCus[j + 1].customer.dept;
                                        
                                        walkCus[j].minuteLeft = walkCus[j + 1].minuteLeft;
                                    }
                                }
                                :: else -> skip;
                            fi
                            index--;  // Number of walking customers is decreasing by 1.
                            i--;  // Do not pass the new walkCus[i].
                        }
                        :: else -> skip;
                    fi
                    i++;
                }
            od

            if
                :: isClosed && index == 0 -> {
                    // Unsubscribe to the TimeTicking.
                    timeRegistration ! UNSUB, _pid;
                }
                :: else -> skip;
            fi

            timeReply[_pid] ! ACK;

            if
                :: isClosed && index == 0 -> break;
                :: else -> skip;
            fi
        }
    od
}


/* --- DEPARTMENT A LOGIC --- */
/* 3 Doctors share 2 Machines.
   Logic: Doctor needs to acquire a Machine before pulling a patient.
   Fairness: Implemented by shared queues and atomic check of resources.
   Phantom Congestion: 
   - Normal/Insured can only start if (freeMachines > reservedMachines).
   - VIP can start if (freeMachines > 0).
*/
active[3] proctype DeptA_Doctor() {
    byte customerId;
    byte treatTime;
    byte treatTimeSave;
    bool hasMachine = false;
    bool isVIPJob = false;
    mtype:customerType currentCustomerType;
    byte doctorId;

    atomic {
        doctorId = doctorUniversalId_A;
        doctorUniversalId_A++;
    }

    do
        :: {
            // Selection Logic (Critical Section for Resource Management)
            atomic {
                if
                    // 1. VIP (Highest Priority)
                    // Can take a machine if any are physically free (they consume their own reservation).
                    :: nempty(deptQueue_A_VIP) && freeMachines_DeptA > 0 -> {
                        deptQueue_A_VIP ? customerId;
                        freeMachines_DeptA--;
                        reservedMachines_DeptA--; // The "Remote Reservation" is now a "Physical Usage"
                        hasMachine = true;
                        isVIPJob = true;
                        currentCustomerType = VIP;
                    }
                    // 2. Insurance (Middle Priority)
                    // Can ONLY take a machine if free count > reserved count.
                    // (Cannot use a machine that is sitting idle waiting for a walking VIP).
                    :: empty(deptQueue_A_VIP) && nempty(deptQueue_A_INS) && freeMachines_DeptA > reservedMachines_DeptA -> {
                        deptQueue_A_INS ? customerId;
                        freeMachines_DeptA--;
                        hasMachine = true;
                        isVIPJob = false;
                        currentCustomerType = INS;
                    }
                    // 3. Normal (Lowest Priority)
                    // Same logic as Insurance.
                    :: empty(deptQueue_A_VIP) && empty(deptQueue_A_INS) && nempty(deptQueue_A_NORM) && freeMachines_DeptA > reservedMachines_DeptA -> {
                        deptQueue_A_NORM ? customerId;
                        freeMachines_DeptA--;
                        hasMachine = true;
                        isVIPJob = false;
                        currentCustomerType = NORM;
                    }
                    // Exit conditions
                    :: isClosed && empty(deptQueue_A_VIP) && empty(deptQueue_A_INS) && empty(deptQueue_A_NORM) -> break;
                    // Wait state (No patients OR No Machines available)
                fi
            }

            if
                :: hasMachine -> {
                    // Treatment lasts 10 to 20 minutes.
                    select(treatTime : 10..20);
                    treatTimeSave = treatTime;

                    timeRegistration ! SUB, _pid;
                    
                    do
                        :: timeNotify[_pid] ? TICK -> {
                            treatTime--;
                            if
                                :: treatTime == 0 -> {
                                    // Treatment Done
                                    atomic {
                                        freeMachines_DeptA++; // Release Machine
                                        nWaitingCustomer_DeptA--;
                                    }
                                    
                                    printf("\nA - A(n) %e customer with id %d is treated by Doctor %d, from %d to %d (%d minutes). Machines Free: %d\n", currentCustomerType, customerId, doctorId, globalTime - treatTimeSave, globalTime, treatTimeSave, freeMachines_DeptA);

                                    timeRegistration ! UNSUB, _pid;
                                    timeReply[_pid] ! ACK;
                                    break;
                                }
                                :: else -> {
                                    timeReply[_pid] ! ACK;
                                }
                            fi
                        }
                    od
                }
                :: !hasMachine -> skip; // Idle cycle (waiting for patient or machine)
            fi
        }
    od
}
/* --- END DEPARTMENT A LOGIC --- */



/* --- DEPARTMENT B LOGIC --- */

active[2] proctype DeptB_Junior() {
    byte customerId;
    mtype:customerType currentCustomerType;
    byte examTime;
    byte treatTime;
    byte treatTimeSave;
    bool isSevere;

    byte juniorId;

    atomic {
        juniorId = juniorDoctorUniversalId;
        juniorDoctorUniversalId++;
    }
    
    do
        :: {
            // Wait for customer (Priority: INS > NORM)
            atomic {
                if
                    :: nempty(deptQueue_B_Junior_INS) -> {
                        deptQueue_B_Junior_INS ? customerId;
                        currentCustomerType = INS;
                    }
                    :: empty(deptQueue_B_Junior_INS) && nempty(deptQueue_B_Junior_NORM) -> {
                        deptQueue_B_Junior_NORM ? customerId;
                        currentCustomerType = NORM;
                    }
                    :: isClosed && empty(deptQueue_B_Junior_INS) && empty(deptQueue_B_Junior_NORM) -> break; 
                fi
            }
            
            // 1. Examination Phase (3-5 minutes)
            select(examTime : 3..5);
            treatTimeSave = examTime;
            timeRegistration ! SUB, _pid;
            
            do
                :: timeNotify[_pid] ? TICK -> {
                    examTime--;
                    if
                        :: examTime == 0 -> {
                            printf("\nB - A(n) %e customer with id %d is examined by the Junior Doctor %d, from %d to %d (%d minutes).\n", currentCustomerType, customerId, juniorId, globalTime - treatTimeSave, globalTime, treatTimeSave);

                            timeRegistration ! UNSUB, _pid;

                            timeReply[_pid] ! ACK;
                            break;
                        }
                        :: else -> {
                            timeReply[_pid] ! ACK;
                        }
                    fi
                }
            od
            
            // 2. Decision Phase (Mild vs Severe)
            if
                :: 1 -> isSevere = false; // Mild
                :: 1 -> isSevere = true;  // Severe
            fi
            
            if
                :: isSevere -> {
                    // Refer to Senior (isReferral = true)
                    deptQueue_B_Senior ! customerId, currentCustomerType; 
                    // Note: Patient is still in Dept B, so we DO NOT decrement nWaitingCustomer_DeptB yet.
                }
                :: !isSevere -> {
                    // Treat Mild Case (10-15 minutes)
                    select(treatTime : 10..15);
                    treatTimeSave = treatTime;
                    
                    timeRegistration ! SUB, _pid;

                    do
                        :: timeNotify[_pid] ? TICK -> {
                            treatTime--;
                            if
                                :: treatTime == 0 -> {
                                    printf("\nB - A(n) %e customer with id %d is treated by the Junior Doctor %d, from %d to %d (%d minutes).\n", currentCustomerType, customerId, juniorId, globalTime - treatTimeSave, globalTime, treatTimeSave);
                                    // Treatment finished -> Patient leaves Dept B
                                    nWaitingCustomer_DeptB--;
                                    
                                    timeRegistration ! UNSUB, _pid;
                                    timeReply[_pid] ! ACK;
                                    break;
                                }
                                :: else -> {
                                    timeReply[_pid] ! ACK;
                                }
                            fi
                        }
                    od
                }
            fi
        }
    od
}

active proctype DeptB_Senior() {
    byte customerId;
    mtype:customerType currentCustomerType;
    byte treatTime;
    
    byte treatTimeSave;
    
    do
    :: {
        // Wait for customer
        if
            :: deptQueue_B_Senior ? customerId, currentCustomerType -> skip;
            :: isClosed && empty(deptQueue_B_Senior) -> break;
        fi
        
        // Determine Treatment Time
        if
            :: currentCustomerType == VIP -> {
                // VIP or Unchecked: 15-20 minutes
                select(treatTime : 15..20);
            }
            :: else -> {
                // Referred case: 10-15 minutes
                select(treatTime : 10..15);
            }
        fi
        treatTimeSave = treatTime;
        // Perform Treatment
        timeRegistration ! SUB, _pid;
        do
            :: timeNotify[_pid] ? TICK -> {
                treatTime--;
                if
                    :: treatTime == 0 -> {
                        // Treatment finished -> Patient leaves Dept B
                        nWaitingCustomer_DeptB--;
                        
                        printf("\nB - A(n) %e customer with id %d is treated by the Senior Doctor, from %d to %d (%d minutes).\n", currentCustomerType, customerId, globalTime - treatTimeSave, globalTime, treatTimeSave);
                        
                        timeRegistration ! UNSUB, _pid;
                        timeReply[_pid] ! ACK;
                        break;
                    }
                    :: else -> {
                        timeReply[_pid] ! ACK;
                    }
                fi
            }
        od
    }
    od
}

/* --- END DEPARTMENT B LOGIC --- */



active proctype PreOPRoom() {
    byte preOPTime;
    bool isPreselected = false;

    do
        :: {
            if
                :: isPreselected -> skip;
                :: else -> {
                    // Waiting for patient to enter.
                    if
                        :: deptVIPQueue_C ? preOPCustomerID; -> {  // Select the next VIP customer.
                            preOPCustomerType = VIP;
                        }
                        :: deptQueue_C ? preOPCustomerID, preOPCustomerType -> skip;  // Select the next customer in the queue.
                        :: deptQueue_C ?? preOPCustomerID, INS -> skip;  // Select the next INS customer in the queue.

                        :: isClosed && nWaitingCustomer_DeptC == 0 -> break;  // CLOSED.
                    fi
                }
            fi
            isPreselected = false;
            // Staying time is randomly selected from 3-5 minutes.
            select (preOPTime: 3 .. 5);
        
            // Begin the countdown. 
            timeRegistration ! SUB, _pid;

            do
                :: timeNotify[_pid] ? TICK -> {
                    preOPTime--;
                    if
                        :: preOPTime == 0 -> {
                            // Done => Ready for Operating Room.
                            isPreOPReady = true;

                            // Unregister to the ClockTicking.
                            timeRegistration ! UNSUB, _pid;
                            timeReply[_pid] ! ACK;
                            break;
                        }
                        :: else -> skip;
                    fi

                    // Check if the current customer is kicked out or not.
                    if
                        :: preOPCustomerType != VIP -> {
                            if 
                                :: nempty(deptVIPQueue_C) -> {
                                    byte vipId;
                                    deptVIPQueue_C ? vipId 
                                    
                                    // The current customer is kicked out of the Pre-OP room.
                                    deptQueue_C ! preOPCustomerID, preOPCustomerType;  // Requeue the current customer.
                                    
                                    // The next customer is a VIP.
                                    isPreselected = true;
                                    preOPCustomerID = vipId;
                                    preOPCustomerType = VIP;
                                    
                                    // End the countdown.
                                    timeRegistration ! UNSUB, _pid;
                                    timeReply[_pid] ! ACK;
                                    break;
                                }
                                :: empty(deptVIPQueue_C) -> skip;  // There is no VIP atm.
                            fi
                        }
                        :: else -> skip;  // VIP cannot be kicked.
                    fi

                    timeReply[_pid] ! ACK;
                }
            od

            // Waiting for Operating Room, but there is still a risk of being kicked out.
            do
                :: atomic {
                    if
                        :: !isPreOPReady -> break;  // Not waiting anymore.
                        :: isPreOPReady -> {
                            // Check if the current customer is kicked out or not.
                            if
                                :: preOPCustomerType != VIP -> {  
                                    if 
                                        :: nempty(deptVIPQueue_C) -> {
                                            byte vipId;
                                            deptVIPQueue_C ? vipId 
                                            
                                            // The current customer is kicked out of the Pre-OP room.
                                            deptQueue_C ! preOPCustomerID, preOPCustomerType;  // Requeue the current customer.
                                            
                                            // The next customer is a VIP.
                                            isPreselected = true;
                                            preOPCustomerID = vipId;
                                            preOPCustomerType = VIP;

                                            isPreOPReady = false;
                                        }
                                        :: empty(deptVIPQueue_C) -> skip;  // There is no VIP atm.
                                    fi
                                }
                                :: else -> skip;  // VIP cannot be kicked.
                            fi
                        }
                    fi
                } 
            od
        }
    od
}

active[2] proctype OperatingRoom() {
    byte opRoomId;
    atomic {
        opRoomId = operatingRoomUniversalId;
        operatingRoomUniversalId++;
    }

    byte currentCustomerId;
    mtype:customerType currentCustomerType;
    byte operatingTime;
    byte operatingTimeSave;

    do
        :: {
            // Wait for customer ready in Pre-OP room and this OP room to be CLEAN.
            atomic {
                if
                    :: ( opRoom[opRoomId] == CLEAN ) && ( isPreOPReady == true ) -> {
                        currentCustomerId = preOPCustomerID;
                        currentCustomerType = preOPCustomerType;
                        isPreOPReady = false;
                    }
                    :: isClosed && nWaitingCustomer_DeptC == 0 -> break;  // CLOSED.
                fi
            }

            // Surgery time is random from 20 to 30.
            select (operatingTime: 20 .. 30);
            operatingTimeSave = operatingTime;

            // Start the countdown: performing surgery.
            opRoom[opRoomId] = BUSY;
            timeRegistration ! SUB, _pid;
            do
                :: timeNotify[_pid] ? TICK -> {
                    operatingTime--;
                    if
                        :: operatingTime == 0 -> { 
                            // Surgery completed.
                            opRoom[opRoomId] = DIRTY;
                            nWaitingCustomer_DeptC--;

                            printf("\nC - A(n) %e customer with id %d is treated in Operating Room %d, from %d to %d (%d minutes).\n", currentCustomerType, currentCustomerId, opRoomId, globalTime - operatingTimeSave, globalTime, operatingTimeSave);
                            
                            // Unregister to the ClockTicking.
                            timeRegistration ! UNSUB, _pid;
                            timeReply[_pid] ! ACK;
                            break;                                    
                        }
                        :: else -> skip;
                    fi

                    timeReply[_pid] ! ACK;
                }
            od
        }
    od
}

active proctype CleaningTeam() {
    byte cleaningTime;
    byte cleaningRoomId;
    do
        :: {
            // Wait for any of the two room to be DIRTY.
            if
                :: opRoom[0] == DIRTY -> cleaningRoomId = 0;
                :: opRoom[1] == DIRTY -> cleaningRoomId = 1;
                :: isClosed && opRoom[0] != DIRTY && opRoom[1] != DIRTY && nWaitingCustomer_DeptC == 0 -> {  // CLOSED
                    break;
                }
            fi

            // Cleaning time is random from 5 to 10 minutes
            select (cleaningTime: 5 .. 10);
            
            // Start the countdown: cleaning the DIRTY room.
            timeRegistration ! SUB, _pid;

            do
                :: timeNotify[_pid] ? TICK -> {
                    cleaningTime--;
                    if
                        :: cleaningTime == 0 -> {
                            // Done cleaning => Room is clean.
                            opRoom[cleaningRoomId] = CLEAN;

                            // Unregister & break.
                            timeRegistration ! UNSUB, _pid;
                            timeReply[_pid] ! ACK;
                            break;
                        }
                        :: else -> skip;
                    fi

                    timeReply[_pid] ! ACK;
                }
            od
        }
    od
}