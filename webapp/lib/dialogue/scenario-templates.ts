export type ScenarioTemplate = {
  collectionId: string;
  collectionTitle: string;
  collectionSubtitle?: string;
  sceneImage?: string;
  slug: string;
  menuTitle: string;
  setting: string;
};

export const scenarioTemplates: ScenarioTemplate[] = [
  // Train & transit
  {
    collectionId: "train-station",
    collectionTitle: "At the Train Station",
    collectionSubtitle:
      "A traveler talks with station staff. Each scenario adds one new layer.",
    sceneImage: "train-station",
    slug: "buying-a-ticket",
    menuTitle: "Buying a ticket",
    setting:
      "At the ticket counter — a tourist asks which ticket to buy for a day trip.",
  },
  {
    collectionId: "train-station",
    collectionTitle: "At the Train Station",
    collectionSubtitle:
      "A traveler talks with station staff. Each scenario adds one new layer.",
    sceneImage: "train-station",
    slug: "asking-the-platform",
    menuTitle: "Asking the platform",
    setting:
      "On the concourse — a passenger asks which platform the Kyoto train leaves from.",
  },
  {
    collectionId: "train-station",
    collectionTitle: "At the Train Station",
    collectionSubtitle:
      "A traveler talks with station staff. Each scenario adds one new layer.",
    sceneImage: "train-station",
    slug: "missing-the-last-train",
    menuTitle: "Missing the last train",
    setting:
      "At the information desk — a traveler asks about the last departure and alternatives.",
  },
  {
    collectionId: "train-station",
    collectionTitle: "At the Train Station",
    collectionSubtitle:
      "A traveler talks with station staff. Each scenario adds one new layer.",
    sceneImage: "train-station",
    slug: "ic-card-trouble",
    menuTitle: "IC card trouble",
    setting:
      "At the ticket gate — a commuter's Suica won't tap and they ask station staff for help.",
  },
  {
    collectionId: "train-station",
    collectionTitle: "At the Train Station",
    collectionSubtitle:
      "A traveler talks with station staff. Each scenario adds one new layer.",
    sceneImage: "train-station",
    slug: "reserved-seat-confusion",
    menuTitle: "Reserved seat confusion",
    setting:
      "On the platform — a rider isn't sure which car their reserved seat is in.",
  },
  {
    collectionId: "train-station",
    collectionTitle: "At the Train Station",
    collectionSubtitle:
      "A traveler talks with station staff. Each scenario adds one new layer.",
    sceneImage: "train-station",
    slug: "lost-item-on-train",
    menuTitle: "Lost item on the train",
    setting:
      "At the lost-and-found counter — a passenger reports a bag left on the train.",
  },
  {
    collectionId: "train-station",
    collectionTitle: "At the Train Station",
    collectionSubtitle:
      "A traveler talks with station staff. Each scenario adds one new layer.",
    sceneImage: "train-station",
    slug: "directions-inside-station",
    menuTitle: "Directions inside the station",
    setting:
      "Near the ticket gates — a new rider asks how to find the east exit.",
  },
  {
    collectionId: "train-station",
    collectionTitle: "At the Train Station",
    collectionSubtitle:
      "A traveler talks with station staff. Each scenario adds one new layer.",
    sceneImage: "train-station",
    slug: "commuter-pass",
    menuTitle: "Buying a commuter pass",
    setting:
      "At the ticket office — an office worker asks how to get a monthly commuter pass.",
  },
  {
    collectionId: "train-station",
    collectionTitle: "At the Train Station",
    collectionSubtitle:
      "A traveler talks with station staff. Each scenario adds one new layer.",
    sceneImage: "train-station",
    slug: "train-delay",
    menuTitle: "Train delay",
    setting:
      "On the platform — a passenger asks staff how long a delay will last.",
  },
  {
    collectionId: "train-station",
    collectionTitle: "At the Train Station",
    collectionSubtitle:
      "A traveler talks with station staff. Each scenario adds one new layer.",
    sceneImage: "train-station",
    slug: "wrong-stop",
    menuTitle: "Getting off at the wrong stop",
    setting:
      "At a station attendant's window — a student realizes they missed their stop.",
  },

  // Airport & travel
  {
    collectionId: "airport",
    collectionTitle: "At the Airport",
    collectionSubtitle: "Travelers navigate check-in, security, and gates.",
    sceneImage: "airport",
    slug: "checking-luggage",
    menuTitle: "Checking in luggage",
    setting:
      "At the check-in counter — a traveler asks about baggage weight limits and fees.",
  },
  {
    collectionId: "airport",
    collectionTitle: "At the Airport",
    collectionSubtitle: "Travelers navigate check-in, security, and gates.",
    sceneImage: "airport",
    slug: "security-screening",
    menuTitle: "Security screening",
    setting:
      "At security — a passenger asks what to remove from their bag before screening.",
  },
  {
    collectionId: "airport",
    collectionTitle: "At the Airport",
    collectionSubtitle: "Travelers navigate check-in, security, and gates.",
    sceneImage: "airport",
    slug: "gate-change",
    menuTitle: "Gate change",
    setting:
      "Near the departure board — a traveler hears their gate changed and asks for help.",
  },
  {
    collectionId: "airport",
    collectionTitle: "At the Airport",
    collectionSubtitle: "Travelers navigate check-in, security, and gates.",
    sceneImage: "airport",
    slug: "duty-free-shopping",
    menuTitle: "Duty-free shopping",
    setting:
      "At a duty-free shop — a tourist asks if an item can go in carry-on luggage.",
  },
  {
    collectionId: "airport",
    collectionTitle: "At the Airport",
    collectionSubtitle: "Travelers navigate check-in, security, and gates.",
    sceneImage: "airport",
    slug: "immigration-basics",
    menuTitle: "Immigration basics",
    setting:
      "At immigration — an officer asks a visitor about their purpose and length of stay.",
  },
  {
    collectionId: "airport",
    collectionTitle: "At the Airport",
    collectionSubtitle: "Travelers navigate check-in, security, and gates.",
    sceneImage: "airport",
    slug: "lost-passport",
    menuTitle: "Lost passport",
    setting:
      "At the information counter — a traveler reports a missing passport.",
  },
  {
    collectionId: "airport",
    collectionTitle: "At the Airport",
    collectionSubtitle: "Travelers navigate check-in, security, and gates.",
    sceneImage: "airport",
    slug: "airport-wifi",
    menuTitle: "Airport Wi‑Fi",
    setting:
      "Near a seating area — a passenger asks how to connect to airport Wi‑Fi.",
  },
  {
    collectionId: "airport",
    collectionTitle: "At the Airport",
    collectionSubtitle: "Travelers navigate check-in, security, and gates.",
    sceneImage: "airport",
    slug: "currency-exchange",
    menuTitle: "Currency exchange",
    setting:
      "At a currency exchange booth — a tourist asks about rates and card acceptance.",
  },

  // Hotel & lodging
  {
    collectionId: "hotel",
    collectionTitle: "At the Hotel",
    collectionSubtitle: "Guests check in, ask for help, and settle small problems.",
    sceneImage: "hotel",
    slug: "checking-in",
    menuTitle: "Checking in",
    setting:
      "At the front desk — a guest gives their name and asks about check-out time.",
  },
  {
    collectionId: "hotel",
    collectionTitle: "At the Hotel",
    collectionSubtitle: "Guests check in, ask for help, and settle small problems.",
    sceneImage: "hotel",
    slug: "room-not-ready",
    menuTitle: "Room not ready",
    setting:
      "At reception — a guest arrives early and asks to store luggage until check-in.",
  },
  {
    collectionId: "hotel",
    collectionTitle: "At the Hotel",
    collectionSubtitle: "Guests check in, ask for help, and settle small problems.",
    sceneImage: "hotel",
    slug: "broken-ac",
    menuTitle: "Broken AC",
    setting:
      "On the phone to the front desk — a guest reports the air conditioner isn't working.",
  },
  {
    collectionId: "hotel",
    collectionTitle: "At the Hotel",
    collectionSubtitle: "Guests check in, ask for help, and settle small problems.",
    sceneImage: "hotel",
    slug: "extra-towels",
    menuTitle: "Extra towels",
    setting:
      "At the front desk — a guest asks housekeeping for more towels.",
  },
  {
    collectionId: "hotel",
    collectionTitle: "At the Hotel",
    collectionSubtitle: "Guests check in, ask for help, and settle small problems.",
    sceneImage: "hotel",
    slug: "late-checkout",
    menuTitle: "Late checkout",
    setting:
      "At the front desk — a guest asks to extend checkout by two hours.",
  },
  {
    collectionId: "hotel",
    collectionTitle: "At the Hotel",
    collectionSubtitle: "Guests check in, ask for help, and settle small problems.",
    sceneImage: "hotel",
    slug: "breakfast-hours",
    menuTitle: "Breakfast hours",
    setting:
      "At the front desk — a guest asks where and when breakfast is served.",
  },
  {
    collectionId: "hotel",
    collectionTitle: "At the Hotel",
    collectionSubtitle: "Guests check in, ask for help, and settle small problems.",
    sceneImage: "hotel",
    slug: "lost-room-key",
    menuTitle: "Lost room key",
    setting:
      "At reception — a guest reports a missing key card and asks for a replacement.",
  },
  {
    collectionId: "hotel",
    collectionTitle: "At the Hotel",
    collectionSubtitle: "Guests check in, ask for help, and settle small problems.",
    sceneImage: "hotel",
    slug: "wake-up-call",
    menuTitle: "Wake-up call",
    setting:
      "On the phone to the front desk — a business traveler requests a morning wake-up call.",
  },

  // Restaurant & café
  {
    collectionId: "restaurant",
    collectionTitle: "At the Restaurant",
    collectionSubtitle: "Customers order, ask questions, and handle small mix-ups.",
    sceneImage: "restaurant",
    slug: "getting-seated",
    menuTitle: "Getting seated",
    setting:
      "At the entrance — a customer asks for a table for two by the window.",
  },
  {
    collectionId: "restaurant",
    collectionTitle: "At the Restaurant",
    collectionSubtitle: "Customers order, ask questions, and handle small mix-ups.",
    sceneImage: "restaurant",
    slug: "ordering-lunch-set",
    menuTitle: "Ordering a lunch set",
    setting:
      "At the table — a customer chooses a set meal and asks about the drink options.",
  },
  {
    collectionId: "restaurant",
    collectionTitle: "At the Restaurant",
    collectionSubtitle: "Customers order, ask questions, and handle small mix-ups.",
    sceneImage: "restaurant",
    slug: "allergy-question",
    menuTitle: "Allergy question",
    setting:
      "At the table — a customer asks if a dish contains shellfish.",
  },
  {
    collectionId: "restaurant",
    collectionTitle: "At the Restaurant",
    collectionSubtitle: "Customers order, ask questions, and handle small mix-ups.",
    sceneImage: "restaurant",
    slug: "spicy-level",
    menuTitle: "Spicy level",
    setting:
      "At the counter — a customer asks how spicy the curry is.",
  },
  {
    collectionId: "restaurant",
    collectionTitle: "At the Restaurant",
    collectionSubtitle: "Customers order, ask questions, and handle small mix-ups.",
    sceneImage: "restaurant",
    slug: "splitting-the-bill",
    menuTitle: "Splitting the bill",
    setting:
      "At the table — friends ask the server if they can pay separately.",
  },
  {
    collectionId: "restaurant",
    collectionTitle: "At the Restaurant",
    collectionSubtitle: "Customers order, ask questions, and handle small mix-ups.",
    sceneImage: "restaurant",
    slug: "takeout-order",
    menuTitle: "Takeout order",
    setting:
      "At the counter — a customer orders a bento to go and asks when it will be ready.",
  },
  {
    collectionId: "restaurant",
    collectionTitle: "At the Restaurant",
    collectionSubtitle: "Customers order, ask questions, and handle small mix-ups.",
    sceneImage: "restaurant",
    slug: "wrong-order",
    menuTitle: "Wrong order",
    setting:
      "At the table — a customer politely says the dish isn't what they ordered.",
  },
  {
    collectionId: "restaurant",
    collectionTitle: "At the Restaurant",
    collectionSubtitle: "Customers order, ask questions, and handle small mix-ups.",
    sceneImage: "restaurant",
    slug: "asking-for-check",
    menuTitle: "Asking for the check",
    setting:
      "At the table — a customer is ready to pay and asks for the bill.",
  },
  {
    collectionId: "restaurant",
    collectionTitle: "At the Restaurant",
    collectionSubtitle: "Customers order, ask questions, and handle small mix-ups.",
    sceneImage: "restaurant",
    slug: "cafe-custom-order",
    menuTitle: "Café custom order",
    setting:
      "At the café counter — a customer asks for oat milk and less sugar.",
  },
  {
    collectionId: "restaurant",
    collectionTitle: "At the Restaurant",
    collectionSubtitle: "Customers order, ask questions, and handle small mix-ups.",
    sceneImage: "restaurant",
    slug: "reservation-confirmation",
    menuTitle: "Reservation confirmation",
    setting:
      "At the entrance — a guest confirms their name and party size for a reservation.",
  },

  // Convenience store & supermarket
  {
    collectionId: "convenience-store",
    collectionTitle: "At the Convenience Store",
    collectionSubtitle: "Quick errands, small questions, everyday shopping.",
    sceneImage: "convenience-store",
    slug: "finding-an-item",
    menuTitle: "Finding an item",
    setting:
      "In the aisles — a shopper asks a clerk where the rice crackers are.",
  },
  {
    collectionId: "convenience-store",
    collectionTitle: "At the Convenience Store",
    collectionSubtitle: "Quick errands, small questions, everyday shopping.",
    sceneImage: "convenience-store",
    slug: "heating-food",
    menuTitle: "Heating food",
    setting:
      "At the counter — a customer asks staff to microwave their bento.",
  },
  {
    collectionId: "convenience-store",
    collectionTitle: "At the Convenience Store",
    collectionSubtitle: "Quick errands, small questions, everyday shopping.",
    sceneImage: "convenience-store",
    slug: "in-store-atm",
    menuTitle: "In-store ATM",
    setting:
      "Near the ATM — a customer asks how to use the in-store cash machine.",
  },
  {
    collectionId: "convenience-store",
    collectionTitle: "At the Convenience Store",
    collectionSubtitle: "Quick errands, small questions, everyday shopping.",
    sceneImage: "convenience-store",
    slug: "points-card",
    menuTitle: "Points card",
    setting:
      "At the register — a customer asks if they can use a loyalty points card.",
  },
  {
    collectionId: "convenience-store",
    collectionTitle: "At the Convenience Store",
    collectionSubtitle: "Quick errands, small questions, everyday shopping.",
    sceneImage: "convenience-store",
    slug: "bag-request",
    menuTitle: "Bag request",
    setting:
      "At checkout — a customer asks for a bag and whether it costs extra.",
  },
  {
    collectionId: "convenience-store",
    collectionTitle: "At the Convenience Store",
    collectionSubtitle: "Quick errands, small questions, everyday shopping.",
    sceneImage: "convenience-store",
    slug: "sale-items",
    menuTitle: "Sale items",
    setting:
      "In the aisle — a shopper asks when a discounted item goes back to full price.",
  },
  {
    collectionId: "convenience-store",
    collectionTitle: "At the Convenience Store",
    collectionSubtitle: "Quick errands, small questions, everyday shopping.",
    sceneImage: "convenience-store",
    slug: "returning-product",
    menuTitle: "Returning a product",
    setting:
      "At the counter — a customer asks about returning a broken product.",
  },
  {
    collectionId: "convenience-store",
    collectionTitle: "At the Convenience Store",
    collectionSubtitle: "Quick errands, small questions, everyday shopping.",
    sceneImage: "convenience-store",
    slug: "self-checkout-help",
    menuTitle: "Self-checkout help",
    setting:
      "At self-checkout — a shopper can't scan a barcode and asks staff for help.",
  },

  // Library & study
  {
    collectionId: "library",
    collectionTitle: "At the Library",
    collectionSubtitle: "Students and readers ask for help finding resources.",
    sceneImage: "library",
    slug: "starting-to-study",
    menuTitle: "Starting to study",
    setting:
      "At the front desk — a student asks where the quiet reading area is.",
  },
  {
    collectionId: "library",
    collectionTitle: "At the Library",
    collectionSubtitle: "Students and readers ask for help finding resources.",
    sceneImage: "library",
    slug: "borrowing-a-book",
    menuTitle: "Borrowing a book",
    setting:
      "At the circulation desk — a patron asks how long they can keep a book.",
  },
  {
    collectionId: "library",
    collectionTitle: "At the Library",
    collectionSubtitle: "Students and readers ask for help finding resources.",
    sceneImage: "library",
    slug: "overdue-books",
    menuTitle: "Overdue books",
    setting:
      "At the circulation desk — a patron asks about late fees on overdue books.",
  },
  {
    collectionId: "library",
    collectionTitle: "At the Library",
    collectionSubtitle: "Students and readers ask for help finding resources.",
    sceneImage: "library",
    slug: "study-room",
    menuTitle: "Study room",
    setting:
      "At the front desk — a student asks to reserve a small group study room.",
  },
  {
    collectionId: "library",
    collectionTitle: "At the Library",
    collectionSubtitle: "Students and readers ask for help finding resources.",
    sceneImage: "library",
    slug: "printing-documents",
    menuTitle: "Printing documents",
    setting:
      "Near the printer — a patron asks how to use the library printer.",
  },
  {
    collectionId: "library",
    collectionTitle: "At the Library",
    collectionSubtitle: "Students and readers ask for help finding resources.",
    sceneImage: "library",
    slug: "finding-textbooks",
    menuTitle: "Finding textbooks",
    setting:
      "In the stacks — a reader asks where the N5 Japanese textbooks are.",
  },

  // School & university
  {
    collectionId: "school",
    collectionTitle: "At School",
    collectionSubtitle: "Classmates and teachers in everyday campus situations.",
    sceneImage: "school",
    slug: "first-day-introduction",
    menuTitle: "First-day introduction",
    setting:
      "In the classroom — a student introduces themselves to a classmate on the first day.",
  },
  {
    collectionId: "school",
    collectionTitle: "At School",
    collectionSubtitle: "Classmates and teachers in everyday campus situations.",
    sceneImage: "school",
    slug: "asking-for-notes",
    menuTitle: "Asking for notes",
    setting:
      "After class — a student who was absent asks a classmate for yesterday's notes.",
  },
  {
    collectionId: "school",
    collectionTitle: "At School",
    collectionSubtitle: "Classmates and teachers in everyday campus situations.",
    sceneImage: "school",
    slug: "club-recruitment",
    menuTitle: "Club recruitment",
    setting:
      "In the hallway — a senpai invites a freshman to join their club.",
  },
  {
    collectionId: "school",
    collectionTitle: "At School",
    collectionSubtitle: "Classmates and teachers in everyday campus situations.",
    sceneImage: "school",
    slug: "changing-classrooms",
    menuTitle: "Changing classrooms",
    setting:
      "In the corridor — a student asks which room the next class is in.",
  },
  {
    collectionId: "school",
    collectionTitle: "At School",
    collectionSubtitle: "Classmates and teachers in everyday campus situations.",
    sceneImage: "school",
    slug: "borrowing-textbook",
    menuTitle: "Borrowing a textbook",
    setting:
      "In the classroom — a student asks to borrow a dictionary briefly.",
  },
  {
    collectionId: "school",
    collectionTitle: "At School",
    collectionSubtitle: "Classmates and teachers in everyday campus situations.",
    sceneImage: "school",
    slug: "presentation-extension",
    menuTitle: "Presentation extension",
    setting:
      "After class — a nervous student asks the teacher for a one-day presentation extension.",
  },
  {
    collectionId: "school",
    collectionTitle: "At School",
    collectionSubtitle: "Classmates and teachers in everyday campus situations.",
    sceneImage: "school",
    slug: "cafeteria-lunch",
    menuTitle: "Cafeteria lunch",
    setting:
      "In the cafeteria — students compare today's menu and prices.",
  },
  {
    collectionId: "school",
    collectionTitle: "At School",
    collectionSubtitle: "Classmates and teachers in everyday campus situations.",
    sceneImage: "school",
    slug: "lost-student-id",
    menuTitle: "Lost student ID",
    setting:
      "At the school office — a student reports a lost student ID card.",
  },

  // Work & office
  {
    collectionId: "office",
    collectionTitle: "At the Office",
    collectionSubtitle: "Coworkers coordinate tasks, schedules, and polite requests.",
    sceneImage: "office",
    slug: "morning-greeting",
    menuTitle: "Morning greeting",
    setting:
      "In the office — a new hire greets coworkers on their first day.",
  },
  {
    collectionId: "office",
    collectionTitle: "At the Office",
    collectionSubtitle: "Coworkers coordinate tasks, schedules, and polite requests.",
    sceneImage: "office",
    slug: "asking-for-help",
    menuTitle: "Asking for help",
    setting:
      "At a desk — a junior staff member asks a senior colleague for task clarification.",
  },
  {
    collectionId: "office",
    collectionTitle: "At the Office",
    collectionSubtitle: "Coworkers coordinate tasks, schedules, and polite requests.",
    sceneImage: "office",
    slug: "scheduling-meeting",
    menuTitle: "Scheduling a meeting",
    setting:
      "By the coffee machine — a coworker proposes times for a short meeting.",
  },
  {
    collectionId: "office",
    collectionTitle: "At the Office",
    collectionSubtitle: "Coworkers coordinate tasks, schedules, and polite requests.",
    sceneImage: "office",
    slug: "calling-in-sick",
    menuTitle: "Calling in sick",
    setting:
      "On the phone — an employee tells their manager they can't come in today.",
  },
  {
    collectionId: "office",
    collectionTitle: "At the Office",
    collectionSubtitle: "Coworkers coordinate tasks, schedules, and polite requests.",
    sceneImage: "office",
    slug: "leaving-early",
    menuTitle: "Leaving early",
    setting:
      "At a desk — a worker asks their manager to leave early for a doctor visit.",
  },
  {
    collectionId: "office",
    collectionTitle: "At the Office",
    collectionSubtitle: "Coworkers coordinate tasks, schedules, and polite requests.",
    sceneImage: "office",
    slug: "printer-jam",
    menuTitle: "Printer jam",
    setting:
      "Near the printer — staff ask IT how to fix a jammed office printer.",
  },
  {
    collectionId: "office",
    collectionTitle: "At the Office",
    collectionSubtitle: "Coworkers coordinate tasks, schedules, and polite requests.",
    sceneImage: "office",
    slug: "client-phone-call",
    menuTitle: "Client phone call",
    setting:
      "At reception — staff take a basic phone message for a colleague.",
  },
  {
    collectionId: "office",
    collectionTitle: "At the Office",
    collectionSubtitle: "Coworkers coordinate tasks, schedules, and polite requests.",
    sceneImage: "office",
    slug: "business-card-exchange",
    menuTitle: "Business card exchange",
    setting:
      "In a meeting room — two professionals exchange business cards politely.",
  },

  // Hospital & pharmacy
  {
    collectionId: "hospital",
    collectionTitle: "At the Hospital",
    collectionSubtitle: "Patients describe symptoms and pick up prescriptions.",
    sceneImage: "hospital",
    slug: "making-appointment",
    menuTitle: "Making an appointment",
    setting:
      "At reception — a patient books a visit for a sore throat.",
  },
  {
    collectionId: "hospital",
    collectionTitle: "At the Hospital",
    collectionSubtitle: "Patients describe symptoms and pick up prescriptions.",
    sceneImage: "hospital",
    slug: "describing-symptoms",
    menuTitle: "Describing symptoms",
    setting:
      "In the exam room — a patient explains fever and headache to a nurse.",
  },
  {
    collectionId: "hospital",
    collectionTitle: "At the Hospital",
    collectionSubtitle: "Patients describe symptoms and pick up prescriptions.",
    sceneImage: "hospital",
    slug: "picking-up-prescription",
    menuTitle: "Picking up prescription",
    setting:
      "At the pharmacy counter — a patient asks when their medicine will be ready.",
  },
  {
    collectionId: "hospital",
    collectionTitle: "At the Hospital",
    collectionSubtitle: "Patients describe symptoms and pick up prescriptions.",
    sceneImage: "hospital",
    slug: "medicine-instructions",
    menuTitle: "Medicine instructions",
    setting:
      "At the pharmacy — a pharmacist explains how many times a day to take medicine.",
  },
  {
    collectionId: "hospital",
    collectionTitle: "At the Hospital",
    collectionSubtitle: "Patients describe symptoms and pick up prescriptions.",
    sceneImage: "hospital",
    slug: "insurance-question",
    menuTitle: "Insurance question",
    setting:
      "At reception — a patient asks if their health insurance is accepted.",
  },
  {
    collectionId: "hospital",
    collectionTitle: "At the Hospital",
    collectionSubtitle: "Patients describe symptoms and pick up prescriptions.",
    sceneImage: "hospital",
    slug: "hospital-directions",
    menuTitle: "Hospital directions",
    setting:
      "In the lobby — a visitor asks where the radiology department is.",
  },

  // Post office & city services
  {
    collectionId: "post-office",
    collectionTitle: "At the Post Office",
    collectionSubtitle: "Sending mail, filling forms, and everyday city errands.",
    sceneImage: "post-office",
    slug: "sending-package",
    menuTitle: "Sending a package",
    setting:
      "At the counter — a customer asks for the cheapest way to send a box overseas.",
  },
  {
    collectionId: "post-office",
    collectionTitle: "At the Post Office",
    collectionSubtitle: "Sending mail, filling forms, and everyday city errands.",
    sceneImage: "post-office",
    slug: "buying-stamps",
    menuTitle: "Buying stamps",
    setting:
      "At the counter — a customer needs stamps for postcards.",
  },
  {
    collectionId: "post-office",
    collectionTitle: "At the Post Office",
    collectionSubtitle: "Sending mail, filling forms, and everyday city errands.",
    sceneImage: "post-office",
    slug: "filling-out-form",
    menuTitle: "Filling out a form",
    setting:
      "At the service window — a clerk helps a resident with a simple application form.",
  },
  {
    collectionId: "post-office",
    collectionTitle: "At the Post Office",
    collectionSubtitle: "Sending mail, filling forms, and everyday city errands.",
    sceneImage: "post-office",
    slug: "lost-wallet-report",
    menuTitle: "Lost wallet report",
    setting:
      "At the police box — a resident asks where to report a lost wallet.",
  },
  {
    collectionId: "post-office",
    collectionTitle: "At the Post Office",
    collectionSubtitle: "Sending mail, filling forms, and everyday city errands.",
    sceneImage: "post-office",
    slug: "residence-card-question",
    menuTitle: "Residence card question",
    setting:
      "At the city office — a foreign resident asks about residence card renewal timing.",
  },

  // Shopping & services
  {
    collectionId: "shopping",
    collectionTitle: "Shopping & Services",
    collectionSubtitle: "Trying on clothes, haircuts, repairs, and returns.",
    sceneImage: "shopping",
    slug: "trying-on-clothes",
    menuTitle: "Trying on clothes",
    setting:
      "On the shop floor — a shopper asks for a different size in the fitting room.",
  },
  {
    collectionId: "shopping",
    collectionTitle: "Shopping & Services",
    collectionSubtitle: "Trying on clothes, haircuts, repairs, and returns.",
    sceneImage: "shopping",
    slug: "returning-shirt",
    menuTitle: "Returning a shirt",
    setting:
      "At the register — a customer asks about exchanging a shirt without a receipt.",
  },
  {
    collectionId: "shopping",
    collectionTitle: "Shopping & Services",
    collectionSubtitle: "Trying on clothes, haircuts, repairs, and returns.",
    sceneImage: "shopping",
    slug: "electronics-help",
    menuTitle: "Electronics help",
    setting:
      "At the electronics counter — a customer asks which charger fits their phone.",
  },
  {
    collectionId: "shopping",
    collectionTitle: "Shopping & Services",
    collectionSubtitle: "Trying on clothes, haircuts, repairs, and returns.",
    sceneImage: "shopping",
    slug: "haircut-request",
    menuTitle: "Haircut request",
    setting:
      "In the salon chair — a customer asks for a trim and shows a reference photo.",
  },
  {
    collectionId: "shopping",
    collectionTitle: "Shopping & Services",
    collectionSubtitle: "Trying on clothes, haircuts, repairs, and returns.",
    sceneImage: "shopping",
    slug: "dry-cleaning-pickup",
    menuTitle: "Dry cleaning pickup",
    setting:
      "At the dry cleaner — a customer asks if their order is ready.",
  },
  {
    collectionId: "shopping",
    collectionTitle: "Shopping & Services",
    collectionSubtitle: "Trying on clothes, haircuts, repairs, and returns.",
    sceneImage: "shopping",
    slug: "shoe-repair",
    menuTitle: "Shoe repair",
    setting:
      "At a repair shop — a customer asks how long heel repair will take.",
  },
  {
    collectionId: "shopping",
    collectionTitle: "Shopping & Services",
    collectionSubtitle: "Trying on clothes, haircuts, repairs, and returns.",
    sceneImage: "shopping",
    slug: "gift-wrapping",
    menuTitle: "Gift wrapping",
    setting:
      "At the gift counter — a shopper asks for wrapping and a message card.",
  },
  {
    collectionId: "shopping",
    collectionTitle: "Shopping & Services",
    collectionSubtitle: "Trying on clothes, haircuts, repairs, and returns.",
    sceneImage: "shopping",
    slug: "warranty-question",
    menuTitle: "Warranty question",
    setting:
      "At the register — a buyer asks how long a product warranty lasts.",
  },

  // Home & daily life
  {
    collectionId: "home",
    collectionTitle: "At Home",
    collectionSubtitle: "Neighbors, landlords, deliveries, and household errands.",
    sceneImage: "home",
    slug: "leaking-faucet",
    menuTitle: "Leaking faucet",
    setting:
      "On the phone — a tenant reports a leaking faucet to the landlord.",
  },
  {
    collectionId: "home",
    collectionTitle: "At Home",
    collectionSubtitle: "Neighbors, landlords, deliveries, and household errands.",
    sceneImage: "home",
    slug: "neighbor-introduction",
    menuTitle: "Neighbor introduction",
    setting:
      "At the apartment door — a new resident greets the person next door.",
  },
  {
    collectionId: "home",
    collectionTitle: "At Home",
    collectionSubtitle: "Neighbors, landlords, deliveries, and household errands.",
    sceneImage: "home",
    slug: "missed-delivery",
    menuTitle: "Missed delivery",
    setting:
      "On the phone — a resident asks how to reschedule a missed package delivery.",
  },
  {
    collectionId: "home",
    collectionTitle: "At Home",
    collectionSubtitle: "Neighbors, landlords, deliveries, and household errands.",
    sceneImage: "home",
    slug: "trash-rules",
    menuTitle: "Trash rules",
    setting:
      "In the hallway — a new resident asks what day burnable trash goes out.",
  },
  {
    collectionId: "home",
    collectionTitle: "At Home",
    collectionSubtitle: "Neighbors, landlords, deliveries, and household errands.",
    sceneImage: "home",
    slug: "borrowing-sugar",
    menuTitle: "Borrowing sugar",
    setting:
      "At a neighbor's door — a resident knocks to borrow a small ingredient.",
  },
  {
    collectionId: "home",
    collectionTitle: "At Home",
    collectionSubtitle: "Neighbors, landlords, deliveries, and household errands.",
    sceneImage: "home",
    slug: "internet-setup",
    menuTitle: "Internet setup",
    setting:
      "On a support call — a resident asks about a home internet connection issue.",
  },
  {
    collectionId: "home",
    collectionTitle: "At Home",
    collectionSubtitle: "Neighbors, landlords, deliveries, and household errands.",
    sceneImage: "home",
    slug: "laundry-check",
    menuTitle: "Laundry check",
    setting:
      "At home — a family member asks if the laundry is done.",
  },

  // Out and about
  {
    collectionId: "out-and-about",
    collectionTitle: "Out and About",
    collectionSubtitle: "Parks, festivals, bikes, museums, and travel moments.",
    sceneImage: "out-and-about",
    slug: "weather-forecast",
    menuTitle: "Weather forecast",
    setting:
      "At a trailhead — a hiker asks if rain is expected this afternoon.",
  },
  {
    collectionId: "out-and-about",
    collectionTitle: "Out and About",
    collectionSubtitle: "Parks, festivals, bikes, museums, and travel moments.",
    sceneImage: "out-and-about",
    slug: "renting-a-bike",
    menuTitle: "Renting a bike",
    setting:
      "At a rental shop — a tourist asks about pricing and where to return the bike.",
  },
  {
    collectionId: "out-and-about",
    collectionTitle: "Out and About",
    collectionSubtitle: "Parks, festivals, bikes, museums, and travel moments.",
    sceneImage: "out-and-about",
    slug: "park-directions",
    menuTitle: "Park directions",
    setting:
      "On the street — a visitor asks how to walk to the nearest park.",
  },
  {
    collectionId: "out-and-about",
    collectionTitle: "Out and About",
    collectionSubtitle: "Parks, festivals, bikes, museums, and travel moments.",
    sceneImage: "out-and-about",
    slug: "museum-ticket",
    menuTitle: "Museum ticket",
    setting:
      "At the museum entrance — a visitor asks about student discount admission.",
  },
  {
    collectionId: "out-and-about",
    collectionTitle: "Out and About",
    collectionSubtitle: "Parks, festivals, bikes, museums, and travel moments.",
    sceneImage: "out-and-about",
    slug: "festival-food-stall",
    menuTitle: "Festival food stall",
    setting:
      "At a summer festival — a visitor orders yakitori and asks what it is.",
  },
  {
    collectionId: "out-and-about",
    collectionTitle: "Out and About",
    collectionSubtitle: "Parks, festivals, bikes, museums, and travel moments.",
    sceneImage: "out-and-about",
    slug: "hot-spring-etiquette",
    menuTitle: "Hot spring etiquette",
    setting:
      "At an onsen entrance — a first-timer asks about bathing rules.",
  },
  {
    collectionId: "out-and-about",
    collectionTitle: "Out and About",
    collectionSubtitle: "Parks, festivals, bikes, museums, and travel moments.",
    sceneImage: "out-and-about",
    slug: "lost-child",
    menuTitle: "Lost child",
    setting:
      "At a festival — a parent asks staff for help finding their child in the crowd.",
  },
  {
    collectionId: "out-and-about",
    collectionTitle: "Out and About",
    collectionSubtitle: "Parks, festivals, bikes, museums, and travel moments.",
    sceneImage: "out-and-about",
    slug: "group-photo",
    menuTitle: "Group photo",
    setting:
      "At a scenic spot — a tourist asks a passerby to take their group's picture.",
  },
];

export type CollectionTemplate = {
  collectionId: string;
  collectionTitle: string;
  collectionSubtitle?: string;
  sceneImage?: string;
  scenarioCount: number;
};

export const collectionTemplates: CollectionTemplate[] = Array.from(
  scenarioTemplates
    .reduce((map, template) => {
      const existing = map.get(template.collectionId);
      if (existing) {
        existing.scenarioCount += 1;
        return map;
      }
      map.set(template.collectionId, {
        collectionId: template.collectionId,
        collectionTitle: template.collectionTitle,
        collectionSubtitle: template.collectionSubtitle,
        sceneImage: template.sceneImage,
        scenarioCount: 1,
      });
      return map;
    }, new Map<string, CollectionTemplate>())
    .values()
);

export function templatesForCollection(collectionId: string): ScenarioTemplate[] {
  return scenarioTemplates.filter(
    (template) => template.collectionId === collectionId
  );
}

export function groupTemplatesByCollection(
  templates: ScenarioTemplate[]
): Array<{ collectionTitle: string; templates: ScenarioTemplate[] }> {
  const groups = new Map<string, ScenarioTemplate[]>();
  for (const template of templates) {
    const group = groups.get(template.collectionTitle) ?? [];
    group.push(template);
    groups.set(template.collectionTitle, group);
  }
  return Array.from(groups.entries()).map(([collectionTitle, items]) => ({
    collectionTitle,
    templates: items,
  }));
}
