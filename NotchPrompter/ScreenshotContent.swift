#if DEBUG
import Foundation

/// Debug builds only: the made-up content in the screenshots (demo scripts, headlines, menu bar clock),
/// per language. Kept out of Localizable.xcstrings on purpose, so none of it ships in the app.
/// The app's own UI in the screenshots comes from the string catalog as usual.
struct ScreenshotContent {
    struct Shot { let headline: String; let detail: String }

    let demoTitle: String
    let demoText: String
    let weeklyTitle: String
    let weeklyText: String
    let youtubeTitle: String
    let youtubeText: String
    /// eye contact, voice, editor, play, private
    let shots: [Shot]
    let clock: String

    /// The content for the language the app shows (`-AppleLanguages`), English if there is none.
    static var current: ScreenshotContent {
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        return all[lang] ?? all[String(lang.prefix(2))] ?? all["en"]!
    }

    private static func s(_ pairs: (String, String)...) -> [Shot] { pairs.map { Shot(headline: $0.0, detail: $0.1) } }

    static let all: [String: ScreenshotContent] = [
        "en": ScreenshotContent(
            demoTitle: "Product launch",
            demoText: """
            Hi everyone, and thanks for joining.

            Today I want to show you something we have been working on for a long time. It is small, but it changes how you show up on camera.

            You know the feeling. You read your notes, and your eyes drift down and away from the people you are talking to. With NotchPrompter, your script sits right under the camera, so you can keep eye contact the whole time.

            It follows your voice as you speak. Take a pause, go off script, and it simply waits for you to come back.
            """,
            weeklyTitle: "Weekly team update",
            weeklyText: "Good morning! Three things this week: the new onboarding, the pricing test, and our plans for the conference.",
            youtubeTitle: "YouTube intro",
            youtubeText: "Hey, welcome back to the channel. Today we are building a tiny Mac app from scratch.",
            shots: s(("Keep eye contact while you read", "Your script sits right under the camera."),
                     ("It follows your voice", "Talk at your own pace. Pause, and it waits for you."),
                     ("Write your scripts right here", "A simple editor. Import Word, Markdown or text files."),
                     ("Or press play", "Steady scrolling. Hover to pause. Tortoise and hare for speed."),
                     ("Invisible to your audience", "Hidden from screen sharing and recordings. Nothing leaves your Mac but speech for Apple’s recogniser.")),
            clock: "Tue 9:41"),

        "nb": ScreenshotContent(
            demoTitle: "Produktlansering",
            demoText: """
            Hei alle sammen, og takk for at dere er med.

            I dag vil jeg vise dere noe vi har jobbet med lenge. Det er lite, men det endrer hvordan du fremstår på kamera.

            Du kjenner følelsen. Du leser notatene dine, og blikket glir ned og bort fra dem du snakker med. Med NotchPrompter står manuset rett under kameraet, så du kan holde øyekontakten hele tiden.

            Den følger stemmen din mens du snakker. Ta en pause, gå bort fra manus, og den venter bare til du kommer tilbake.
            """,
            weeklyTitle: "Ukentlig teamoppdatering",
            weeklyText: "God morgen! Tre ting denne uka: den nye introduksjonen, pristesten og planene våre for konferansen.",
            youtubeTitle: "YouTube-intro",
            youtubeText: "Hei, og velkommen tilbake til kanalen. I dag lager vi en bitteliten Mac-app fra bunnen av.",
            shots: s(("Hold øyekontakten mens du leser", "Manuset står rett under kameraet."),
                     ("Følger stemmen din", "Snakk i ditt eget tempo. Ta en pause, så venter den på deg."),
                     ("Skriv manusene dine rett her", "En enkel redigering. Importer Word-, Markdown- eller tekstfiler."),
                     ("Eller trykk på Spill av", "Jevn rulling. Hold pekeren over for å pause. Skilpadden og haren styrer farten."),
                     ("Usynlig for publikum", "Skjult ved skjermdeling og i opptak. Ingenting forlater Macen utenom tale til Apples talegjenkjenning.")),
            clock: "tir. 09:41"),

        "de": ScreenshotContent(
            demoTitle: "Produktlaunch",
            demoText: """
            Hallo zusammen, und danke, dass ihr dabei seid.

            Heute möchte ich euch etwas zeigen, an dem wir lange gearbeitet haben. Es ist klein, aber es verändert, wie du vor der Kamera wirkst.

            Du kennst das. Du liest deine Notizen, und dein Blick wandert nach unten, weg von den Menschen, mit denen du sprichst. Mit NotchPrompter steht dein Skript direkt unter der Kamera, so hältst du die ganze Zeit Blickkontakt.

            Es folgt deiner Stimme, während du sprichst. Mach eine Pause, weich vom Skript ab, und es wartet einfach, bis du zurückkommst.
            """,
            weeklyTitle: "Wöchentliches Team-Update",
            weeklyText: "Guten Morgen! Drei Themen diese Woche: das neue Onboarding, der Preistest und unsere Pläne für die Konferenz.",
            youtubeTitle: "YouTube-Intro",
            youtubeText: "Hey, willkommen zurück auf dem Kanal. Heute bauen wir eine kleine Mac-App von Grund auf.",
            shots: s(("Halte Blickkontakt, während du liest", "Dein Skript steht direkt unter der Kamera."),
                     ("Folgt deiner Stimme", "Sprich in deinem Tempo. Mach eine Pause, und es wartet auf dich."),
                     ("Schreib deine Skripte direkt hier", "Ein einfacher Editor. Importiere Word-, Markdown- oder Textdateien."),
                     ("Oder drück auf Play", "Gleichmäßiges Scrollen. Zeig darauf, um zu pausieren. Schildkröte und Hase für das Tempo."),
                     ("Unsichtbar für dein Publikum", "Verborgen bei Bildschirmfreigabe und Aufnahmen. Nichts verlässt deinen Mac außer Sprache für Apples Spracherkennung.")),
            clock: "Di. 09:41"),

        "fr": ScreenshotContent(
            demoTitle: "Lancement produit",
            demoText: """
            Bonjour à tous, et merci d’être là.

            Aujourd’hui, je veux vous montrer quelque chose sur lequel nous travaillons depuis longtemps. C’est petit, mais ça change votre façon d’apparaître à l’écran.

            Vous connaissez ça. Vous lisez vos notes, et votre regard descend et s’éloigne de vos interlocuteurs. Avec NotchPrompter, votre texte est juste sous la caméra, pour garder le contact visuel tout du long.

            Il suit votre voix pendant que vous parlez. Faites une pause, improvisez, et il attend simplement votre retour.
            """,
            weeklyTitle: "Point d’équipe hebdo",
            weeklyText: "Bonjour à tous\u{00A0}! Trois sujets cette semaine\u{00A0}: le nouvel accueil des utilisateurs, le test de prix et nos projets pour la conférence.",
            youtubeTitle: "Intro YouTube",
            youtubeText: "Salut, et bon retour sur la chaîne. Aujourd’hui, on crée une petite app Mac de A à Z.",
            shots: s(("Gardez le contact visuel pendant que vous lisez", "Votre texte est juste sous la caméra."),
                     ("Suit votre voix", "Parlez à votre rythme. Faites une pause, il vous attend."),
                     ("Écrivez vos textes ici même", "Un éditeur simple. Importez des fichiers Word, Markdown ou texte."),
                     ("Ou appuyez sur lecture", "Défilement régulier. Survolez pour mettre en pause. La tortue et le lièvre règlent la vitesse."),
                     ("Invisible pour votre public", "Masqué lors du partage d’écran et des enregistrements. Rien ne quitte votre Mac, sauf la parole pour la reconnaissance d’Apple.")),
            clock: "mar. 09:41"),

        "es": ScreenshotContent(
            demoTitle: "Lanzamiento del producto",
            demoText: """
            Hola a todos, y gracias por estar aquí.

            Hoy quiero mostrar algo en lo que llevamos mucho tiempo trabajando. Es algo pequeño, pero cambia cómo te ves ante la cámara.

            Ya sabes lo que pasa. Lees tus notas y tu mirada baja y se aleja de la gente con la que hablas. Con NotchPrompter, tu guion está justo debajo de la cámara, así que mantienes el contacto visual todo el tiempo.

            Sigue tu voz mientras hablas. Haz una pausa, sal del guion, y simplemente espera a que vuelvas.
            """,
            weeklyTitle: "Novedades semanales del equipo",
            weeklyText: "¡Buenos días! Tres cosas esta semana: la nueva bienvenida para usuarios, la prueba de precios y nuestros planes para la conferencia.",
            youtubeTitle: "Intro de YouTube",
            youtubeText: "Hola, bienvenidos de nuevo al canal. Hoy creamos una pequeña app para Mac desde cero.",
            shots: s(("Mantén el contacto visual mientras lees", "Tu guion está justo debajo de la cámara."),
                     ("Sigue tu voz", "Habla a tu ritmo. Haz una pausa y te espera."),
                     ("Escribe tus guiones aquí mismo", "Un editor sencillo. Importa archivos de Word, Markdown o texto."),
                     ("O pulsa reproducir", "Desplazamiento constante. Pasa el puntero por encima para pausar. La tortuga y la liebre ajustan la velocidad."),
                     ("Invisible para tu público", "Oculto al compartir pantalla y en grabaciones. Nada sale de tu Mac, salvo la voz para el reconocimiento de Apple.")),
            clock: "mar 9:41"),

        "it": ScreenshotContent(
            demoTitle: "Lancio del prodotto",
            demoText: """
            Ciao a tutti, e grazie di essere qui.

            Oggi voglio mostrarvi una cosa su cui lavoriamo da molto tempo. È piccola, ma cambia il modo in cui appari in video.

            Ti è già capitato. Leggi gli appunti e lo sguardo scende e si allontana dalle persone con cui parli. Con NotchPrompter, il testo è proprio sotto la fotocamera, così mantieni il contatto visivo tutto il tempo.

            Segue la tua voce mentre parli. Fai una pausa, esci dal copione, e aspetta semplicemente che tu torni.
            """,
            weeklyTitle: "Aggiornamento settimanale del team",
            weeklyText: "Buongiorno! Tre cose questa settimana: il nuovo onboarding, il test sui prezzi e i nostri piani per la conferenza.",
            youtubeTitle: "Intro YouTube",
            youtubeText: "Ciao, bentornati sul canale. Oggi creiamo da zero una piccola app per Mac.",
            shots: s(("Mantieni il contatto visivo mentre leggi", "Il tuo testo è proprio sotto la fotocamera."),
                     ("Segue la tua voce", "Parla al tuo ritmo. Fai una pausa, e ti aspetta."),
                     ("Scrivi i tuoi copioni proprio qui", "Un editor semplice. Importa file Word, Markdown o di testo."),
                     ("Oppure premi play", "Scorrimento costante. Passa sopra con il puntatore per mettere in pausa. Tartaruga e lepre per la velocità."),
                     ("Invisibile al tuo pubblico", "Nascosto nella condivisione schermo e nelle registrazioni. Nulla lascia il tuo Mac, tranne il parlato per il riconoscimento di Apple.")),
            clock: "mar 09:41"),

        "pt-BR": ScreenshotContent(
            demoTitle: "Lançamento do produto",
            demoText: """
            Oi, pessoal, e obrigado por participarem.

            Hoje quero mostrar uma coisa em que estamos trabalhando há muito tempo. É pequena, mas muda como você aparece na câmera.

            Você conhece a sensação. Você lê suas anotações, e o olhar desce e se afasta das pessoas com quem está falando. Com o NotchPrompter, o roteiro fica bem embaixo da câmera, então você mantém o contato visual o tempo todo.

            Ele acompanha a sua voz enquanto você fala. Faça uma pausa, saia do roteiro, e ele simplesmente espera você voltar.
            """,
            weeklyTitle: "Atualização semanal da equipe",
            weeklyText: "Bom dia! Três assuntos nesta semana: o novo onboarding, o teste de preços e nossos planos para a conferência.",
            youtubeTitle: "Intro do YouTube",
            youtubeText: "E aí, bem-vindos de volta ao canal. Hoje vamos criar um pequeno app para Mac do zero.",
            shots: s(("Mantenha o contato visual enquanto lê", "Seu roteiro fica bem embaixo da câmera."),
                     ("Acompanha a sua voz", "Fale no seu ritmo. Faça uma pausa, e ele espera por você."),
                     ("Escreva seus roteiros aqui mesmo", "Um editor simples. Importe arquivos do Word, Markdown ou texto."),
                     ("Ou clique em reproduzir", "Rolagem constante. Passe o cursor por cima para pausar. A tartaruga e a lebre ajustam a velocidade."),
                     ("Invisível para o seu público", "Oculto no compartilhamento de tela e em gravações. Nada sai do seu Mac, exceto a fala para o reconhecimento da Apple.")),
            clock: "ter. 09:41"),

        "pt-PT": ScreenshotContent(
            demoTitle: "Lançamento do produto",
            demoText: """
            Olá a todos, e obrigado por estarem aqui.

            Hoje quero mostrar-vos algo em que temos trabalhado há muito tempo. É pequeno, mas muda a forma como aparece na câmara.

            Conhece a sensação. Lê as suas notas e o olhar desce e foge das pessoas com quem está a falar. Com o NotchPrompter, o seu guião fica mesmo por baixo da câmara, para manter o contacto visual o tempo todo.

            Acompanha a sua voz enquanto fala. Faça uma pausa, saia do guião, e ele simplesmente espera que volte.
            """,
            weeklyTitle: "Ponto de situação semanal",
            weeklyText: "Bom dia! Três coisas esta semana: a nova introdução para utilizadores, o teste de preços e os nossos planos para a conferência.",
            youtubeTitle: "Introdução do YouTube",
            youtubeText: "Olá, bem-vindos de volta ao canal. Hoje vamos criar uma pequena app para Mac do zero.",
            shots: s(("Mantenha o contacto visual enquanto lê", "O seu guião fica mesmo por baixo da câmara."),
                     ("Acompanha a sua voz", "Fale ao seu ritmo. Faça uma pausa e ele espera por si."),
                     ("Escreva os seus guiões aqui mesmo", "Um editor simples. Importe ficheiros Word, Markdown ou de texto."),
                     ("Ou carregue em reproduzir", "Deslocamento constante. Passe o cursor por cima para pausar. A tartaruga e a lebre definem a velocidade."),
                     ("Invisível para o seu público", "Oculto na partilha de ecrã e nas gravações. Nada sai do seu Mac, exceto a fala para o reconhecimento da Apple.")),
            clock: "ter. 09:41"),

        "nl": ScreenshotContent(
            demoTitle: "Productlancering",
            demoText: """
            Hoi allemaal, en bedankt dat jullie er zijn.

            Vandaag wil ik jullie iets laten zien waar we lang aan hebben gewerkt. Het is klein, maar het verandert hoe je overkomt op camera.

            Je kent het wel. Je leest je aantekeningen, en je blik zakt weg van de mensen met wie je praat. Met NotchPrompter staat je script vlak onder de camera, zodat je de hele tijd oogcontact houdt.

            Hij volgt je stem terwijl je praat. Neem een pauze, wijk af van je script, en hij wacht gewoon tot je terugkomt.
            """,
            weeklyTitle: "Wekelijkse teamupdate",
            weeklyText: "Goedemorgen! Drie dingen deze week: de nieuwe onboarding, de prijstest en onze plannen voor de conferentie.",
            youtubeTitle: "YouTube-intro",
            youtubeText: "Hé, welkom terug op het kanaal. Vandaag bouwen we een piepkleine Mac-app vanaf nul.",
            shots: s(("Houd oogcontact terwijl je leest", "Je script staat vlak onder de camera."),
                     ("Volgt je stem", "Praat in je eigen tempo. Pauzeer, en hij wacht op je."),
                     ("Schrijf je scripts hier", "Een eenvoudige editor. Importeer Word-, Markdown- of tekstbestanden."),
                     ("Of druk op afspelen", "Gelijkmatig scrollen. Beweeg de aanwijzer erover om te pauzeren. Schildpad en haas voor de snelheid."),
                     ("Onzichtbaar voor je publiek", "Verborgen bij schermdeling en opnames. Niets verlaat je Mac, behalve spraak voor de spraakherkenning van Apple.")),
            clock: "di 09:41"),

        "sv": ScreenshotContent(
            demoTitle: "Produktlansering",
            demoText: """
            Hej allihop, och tack för att ni är med.

            I dag vill jag visa er något vi har jobbat med länge. Det är litet, men det ändrar hur du tar dig ut i kameran.

            Du känner igen känslan. Du läser dina anteckningar, och blicken glider ner och bort från dem du pratar med. Med NotchPrompter hamnar ditt manus precis under kameran, så att du behåller ögonkontakten hela tiden.

            Den följer din röst medan du pratar. Ta en paus, avvik från manus, och den väntar helt enkelt tills du kommer tillbaka.
            """,
            weeklyTitle: "Veckans teamuppdatering",
            weeklyText: "God morgon! Tre saker den här veckan: den nya introduktionen, pristestet och våra planer för konferensen.",
            youtubeTitle: "YouTube-intro",
            youtubeText: "Hej, och välkommen tillbaka till kanalen. I dag bygger vi en liten Mac-app från grunden.",
            shots: s(("Behåll ögonkontakten medan du läser", "Ditt manus hamnar precis under kameran."),
                     ("Följer din röst", "Prata i din egen takt. Pausa, så väntar den på dig."),
                     ("Skriv dina manus direkt här", "En enkel redigerare. Importera Word-, Markdown- eller textfiler."),
                     ("Eller tryck på spela upp", "Jämn rullning. Håll pekaren över för att pausa. Sköldpaddan och haren styr hastigheten."),
                     ("Osynlig för din publik", "Dold vid skärmdelning och i inspelningar. Inget lämnar din Mac utom tal till Apples taligenkänning.")),
            clock: "tis 09:41"),

        "da": ScreenshotContent(
            demoTitle: "Produktlancering",
            demoText: """
            Hej allesammen, og tak fordi I er med.

            I dag vil jeg vise jer noget, vi har arbejdet på længe. Det er lille, men det ændrer, hvordan du tager dig ud på kamera.

            Du kender følelsen. Du læser dine noter, og blikket glider ned og væk fra dem, du taler med. Med NotchPrompter står dit manuskript lige under kameraet, så du kan holde øjenkontakt hele tiden.

            Den følger din stemme, mens du taler. Hold en pause, gå fra manuskriptet, og den venter bare, til du kommer tilbage.
            """,
            weeklyTitle: "Ugentlig teamopdatering",
            weeklyText: "Godmorgen! Tre ting i denne uge: den nye introduktion, pristesten og vores planer for konferencen.",
            youtubeTitle: "YouTube-intro",
            youtubeText: "Hej, og velkommen tilbage til kanalen. I dag bygger vi en lillebitte Mac-app helt fra bunden.",
            shots: s(("Hold øjenkontakt, mens du læser", "Dit manuskript står lige under kameraet."),
                     ("Følger din stemme", "Tal i dit eget tempo. Hold en pause, så venter den på dig."),
                     ("Skriv dine manuskripter lige her", "En enkel redigering. Importér Word-, Markdown- eller tekstfiler."),
                     ("Eller tryk på afspil", "Jævn rulning. Hold markøren over for at sætte på pause. Skildpadden og haren styrer hastigheden."),
                     ("Usynlig for dit publikum", "Skjult ved skærmdeling og i optagelser. Intet forlader din Mac undtagen tale til Apples talegenkendelse.")),
            clock: "tirs. 09.41"),

        "fi": ScreenshotContent(
            demoTitle: "Tuotelanseeraus",
            demoText: """
            Hei kaikki, ja kiitos, että tulitte mukaan.

            Tänään haluan näyttää teille jotain, minkä parissa olemme työskennelleet pitkään. Se on pieni, mutta se muuttaa sitä, miltä näytät kameralla.

            Tiedät tunteen. Luet muistiinpanojasi, ja katseesi painuu alas ja pois ihmisistä, joille puhut. NotchPrompterin ansiosta käsikirjoitus on aivan kameran alla, joten pidät katsekontaktin koko ajan.

            Se seuraa ääntäsi, kun puhut. Pidä tauko, poikkea käsikirjoituksesta, ja se vain odottaa, kunnes palaat.
            """,
            weeklyTitle: "Tiimin viikkokatsaus",
            weeklyText: "Hyvää huomenta! Kolme asiaa tällä viikolla: uusi käyttöönotto, hintatesti ja suunnitelmamme konferenssia varten.",
            youtubeTitle: "YouTube-intro",
            youtubeText: "Hei, ja tervetuloa takaisin kanavalle. Tänään teemme pienen Mac-sovelluksen alusta alkaen.",
            shots: s(("Pidä katsekontakti lukiessasi", "Käsikirjoitus on aivan kameran alla."),
                     ("Seuraa ääntäsi", "Puhu omaan tahtiisi. Pidä tauko, niin se odottaa sinua."),
                     ("Kirjoita käsikirjoituksesi suoraan tässä", "Yksinkertainen editori. Tuo Word-, Markdown- tai tekstitiedostoja."),
                     ("Tai paina toistoa", "Tasainen vieritys. Pysäytä viemällä osoitin päälle. Kilpikonna ja jänis säätävät nopeutta."),
                     ("Näkymätön yleisöllesi", "Piilossa näytön jakamisessa ja tallenteissa. Macistasi ei lähde mitään paitsi puhe Applen puheentunnistukseen.")),
            clock: "ti 9.41"),

        "pl": ScreenshotContent(
            demoTitle: "Premiera produktu",
            demoText: """
            Cześć wszystkim i dzięki, że jesteście.

            Dziś chcę wam pokazać coś, nad czym pracowaliśmy bardzo długo. To drobiazg, ale zmienia to, jak wypadasz przed kamerą.

            Znasz to uczucie. Czytasz notatki, a twój wzrok ucieka w dół, od ludzi, z którymi rozmawiasz. Z NotchPrompterem twój scenariusz jest tuż pod kamerą, więc przez cały czas utrzymujesz kontakt wzrokowy.

            Podąża za twoim głosem, gdy mówisz. Zrób pauzę, odejdź od scenariusza, a on po prostu poczeka, aż wrócisz.
            """,
            weeklyTitle: "Cotygodniowe podsumowanie zespołu",
            weeklyText: "Dzień dobry! W tym tygodniu trzy sprawy: nowy onboarding, test cen i nasze plany na konferencję.",
            youtubeTitle: "Intro na YouTube",
            youtubeText: "Hej, witajcie z powrotem na kanale. Dziś budujemy od zera malutką aplikację na Maca.",
            shots: s(("Utrzymuj kontakt wzrokowy podczas czytania", "Twój scenariusz jest tuż pod kamerą."),
                     ("Podąża za twoim głosem", "Mów we własnym tempie. Zrób pauzę, a on na ciebie poczeka."),
                     ("Pisz scenariusze właśnie tutaj", "Prosty edytor. Importuj pliki Word, Markdown lub tekstowe."),
                     ("Albo naciśnij Odtwórz", "Równe przewijanie. Najedź kursorem, by wstrzymać. Żółw i zając ustawiają tempo."),
                     ("Niewidoczny dla widzów", "Ukryty podczas udostępniania ekranu i w nagraniach. Nic nie opuszcza twojego Maca poza mową dla rozpoznawania Apple.")),
            clock: "wt. 09:41"),

        "ja": ScreenshotContent(
            demoTitle: "新製品発表",
            demoText: """
            皆さん、こんにちは。ご参加ありがとうございます。

            今日は、私たちが長い間取り組んできたものをお見せします。小さなものですが、カメラの前での印象が変わります。

            よくありますよね。メモを読んでいると、目線が下がって、話している相手からそれてしまう。NotchPrompterなら、原稿がカメラのすぐ下に表示されるので、ずっと目線を合わせたまま話せます。

            話すと、声に合わせて進みます。間を取っても、原稿から外れても、戻ってくるまでちゃんと待ってくれます。
            """,
            weeklyTitle: "週次チームミーティング",
            weeklyText: "おはようございます。今週は3つです。新しいオンボーディング、価格テスト、そしてカンファレンスの計画です。",
            youtubeTitle: "YouTubeのオープニング",
            youtubeText: "どうも、チャンネルへようこそ。今日はMac用の小さなアプリをゼロから作ります。",
            shots: s(("読みながら、目線はそのまま", "原稿はカメラのすぐ下に。"),
                     ("声についてくる", "自分のペースで話せます。止まれば、待ってくれます。"),
                     ("原稿はここで書ける", "シンプルなエディタ。Word、Markdown、テキストファイルを読み込めます。"),
                     ("再生ボタンでも", "一定の速さでスクロール。ポインタを重ねると一時停止。カメとウサギで速度を調整。"),
                     ("見ている人には見えない", "画面共有や画面収録には映りません。Macの外に出るのは、Appleの音声認識に送る音声だけです。")),
            clock: "(火) 9:41"),

        "ko": ScreenshotContent(
            demoTitle: "제품 출시",
            demoText: """
            여러분, 안녕하세요. 함께해 주셔서 감사합니다.

            오늘은 저희가 오랫동안 준비해 온 것을 보여 드리려고 합니다. 작은 것이지만, 카메라 앞에서의 모습을 바꿔 줍니다.

            그런 적 있으시죠. 메모를 읽다 보면 시선이 아래로 내려가서, 이야기하는 사람들에게서 멀어집니다. NotchPrompter를 쓰면 대본이 카메라 바로 아래에 있어서, 처음부터 끝까지 눈을 맞추며 말할 수 있습니다.

            말하는 동안 목소리를 따라갑니다. 잠시 쉬거나 대본에서 벗어나도, 다시 돌아올 때까지 그냥 기다려 줍니다.
            """,
            weeklyTitle: "주간 팀 업데이트",
            weeklyText: "좋은 아침입니다! 이번 주에는 세 가지입니다. 새 온보딩, 가격 테스트, 그리고 컨퍼런스 계획입니다.",
            youtubeTitle: "유튜브 인트로",
            youtubeText: "안녕하세요, 채널에 다시 오신 걸 환영합니다. 오늘은 작은 Mac 앱을 처음부터 만들어 보겠습니다.",
            shots: s(("읽으면서도 시선은 그대로", "대본이 카메라 바로 아래에 있습니다."),
                     ("목소리를 따라갑니다", "내 속도로 말하세요. 잠시 멈추면 기다려 줍니다."),
                     ("대본은 여기서 바로 쓰세요", "간단한 편집기. Word, Markdown, 텍스트 파일을 가져올 수 있습니다."),
                     ("재생 버튼도 있습니다", "일정한 속도로 스크롤. 포인터를 올리면 일시 정지. 거북이와 토끼로 속도 조절."),
                     ("보는 사람에게는 보이지 않습니다", "화면 공유와 녹화에 나타나지 않습니다. Apple 음성 인식에 보내는 음성 외에는 Mac 밖으로 나가지 않습니다.")),
            clock: "(화) 오전 9:41"),

        "zh-Hans": ScreenshotContent(
            demoTitle: "产品发布",
            demoText: """
            大家好，感谢各位的参与。

            今天我想给大家展示一样我们做了很久的东西。它很小，却能改变你在镜头前的样子。

            你一定有过这种感觉。低头看笔记时，目光就往下移，离开了正在听你说话的人。有了 NotchPrompter，讲稿就在摄像头正下方，你可以一直保持眼神交流。

            你说话时，它会跟着你的声音走。停顿一下，或者脱稿发挥，它都会耐心等你回来。
            """,
            weeklyTitle: "团队周报",
            weeklyText: "早上好！本周三件事：新的新手引导、定价测试，以及我们的大会计划。",
            youtubeTitle: "YouTube 开场白",
            youtubeText: "嘿，欢迎回到频道。今天我们从零开始做一个小小的 Mac 应用。",
            shots: s(("边读稿，边保持眼神交流", "讲稿就在摄像头正下方。"),
                     ("跟随你的声音", "按你自己的节奏说。停下来，它就等你。"),
                     ("讲稿就在这里写", "简洁的编辑器。可导入 Word、Markdown 或文本文件。"),
                     ("或者按下播放", "匀速滚动。指针悬停即可暂停。用乌龟和兔子调整速度。"),
                     ("观众看不见", "在屏幕共享和录屏中隐藏。除了发送给 Apple 语音识别的语音，任何内容都不会离开你的 Mac。")),
            clock: "周二 09:41"),

        "zh-Hant": ScreenshotContent(
            demoTitle: "產品發表",
            demoText: """
            大家好，謝謝各位的參與。

            今天我想跟大家展示一個我們做了很久的東西。它很小，卻能改變你在鏡頭前的樣子。

            你一定有過這種感覺。低頭看筆記時，視線就往下移，離開了正在聽你說話的人。有了 NotchPrompter，講稿就在相機正下方，你可以一直保持眼神接觸。

            你說話時，它會跟著你的聲音走。停頓一下，或是脫稿發揮，它都會耐心等你回來。
            """,
            weeklyTitle: "團隊每週更新",
            weeklyText: "早安！這週有三件事：新的新手導覽、定價測試，還有我們的研討會計畫。",
            youtubeTitle: "YouTube 開場",
            youtubeText: "嘿，歡迎回到頻道。今天我們要從零開始做一個小小的 Mac App。",
            shots: s(("邊讀講稿，邊保持眼神接觸", "講稿就在相機正下方。"),
                     ("跟著你的聲音走", "照你自己的節奏說。停下來，它就等你。"),
                     ("講稿就在這裡寫", "簡潔的編輯器。可以匯入 Word、Markdown 或文字檔案。"),
                     ("或者按下播放", "等速捲動。將指標停在上方即可暫停。用烏龜和兔子調整速度。"),
                     ("觀眾看不到", "在螢幕共享和螢幕錄影中隱藏。除了傳送給 Apple 語音辨識的語音，任何內容都不會離開你的 Mac。")),
            clock: "週二 上午9:41"),

        "ru": ScreenshotContent(
            demoTitle: "Запуск продукта",
            demoText: """
            Всем привет, и спасибо, что присоединились.

            Сегодня я хочу показать вам то, над чем мы долго работали. Это мелочь, но она меняет то, как вы выглядите в кадре.

            Знакомое чувство. Вы читаете заметки, и взгляд опускается и уходит от тех, с кем вы говорите. С NotchPrompter ваш текст находится прямо под камерой, так что вы всё время смотрите собеседникам в глаза.

            Он следует за вашим голосом, пока вы говорите. Сделайте паузу, отойдите от текста, и он просто подождёт, пока вы вернётесь.
            """,
            weeklyTitle: "Еженедельная встреча команды",
            weeklyText: "Доброе утро! На этой неделе три темы: новый онбординг, тест цен и наши планы на конференцию.",
            youtubeTitle: "Интро для YouTube",
            youtubeText: "Привет, с возвращением на канал. Сегодня мы с нуля делаем маленькое приложение для Mac.",
            shots: s(("Сохраняйте зрительный контакт во время чтения", "Ваш текст находится прямо под камерой."),
                     ("Следует за вашим голосом", "Говорите в своём темпе. Сделайте паузу, и он подождёт."),
                     ("Пишите сценарии прямо здесь", "Простой редактор. Импорт файлов Word, Markdown и обычного текста."),
                     ("Или включите воспроизведение", "Плавная прокрутка. Наведите указатель, чтобы остановить. Черепаха и заяц задают скорость."),
                     ("Невидим для зрителей", "Скрыт при демонстрации экрана и в записях. С вашего Mac уходит только речь для распознавания Apple.")),
            clock: "Вт 09:41"),

        "uk": ScreenshotContent(
            demoTitle: "Запуск продукту",
            demoText: """
            Усім привіт, і дякую, що долучилися.

            Сьогодні я хочу показати вам те, над чим ми довго працювали. Це дрібниця, але вона змінює те, як ви виглядаєте в кадрі.

            Знайоме відчуття. Ви читаєте нотатки, і погляд опускається й тікає від людей, з якими ви говорите. З NotchPrompter ваш текст розташований просто під камерою, тож ви весь час дивитеся співрозмовникам в очі.

            Він стежить за вашим голосом, поки ви говорите. Зробіть паузу, відійдіть від тексту, і він просто зачекає, доки ви повернетеся.
            """,
            weeklyTitle: "Щотижнева зустріч команди",
            weeklyText: "Доброго ранку! Цього тижня три теми: новий онбординг, тест цін і наші плани на конференцію.",
            youtubeTitle: "Інтро для YouTube",
            youtubeText: "Привіт, з поверненням на канал. Сьогодні ми з нуля створюємо маленький застосунок для Mac.",
            shots: s(("Зберігайте зоровий контакт під час читання", "Ваш текст розташований просто під камерою."),
                     ("Стежить за вашим голосом", "Говоріть у своєму темпі. Зробіть паузу, і він зачекає."),
                     ("Пишіть сценарії просто тут", "Простий редактор. Імпорт файлів Word, Markdown і звичайного тексту."),
                     ("Або ввімкніть відтворення", "Рівне прокручування. Наведіть курсор, щоб призупинити. Черепаха й заєць задають швидкість."),
                     ("Невидимий для глядачів", "Прихований під час показу екрана та в записах. З вашого Mac іде лише мовлення для розпізнавання Apple.")),
            clock: "Вт 09:41"),

        "tr": ScreenshotContent(
            demoTitle: "Ürün lansmanı",
            demoText: """
            Herkese merhaba, katıldığınız için teşekkürler.

            Bugün size uzun zamandır üzerinde çalıştığımız bir şeyi göstermek istiyorum. Küçük bir şey, ama kamerada nasıl göründüğünüzü değiştiriyor.

            Bu hissi bilirsiniz. Notlarınızı okursunuz ve gözleriniz aşağı kayıp konuştuğunuz kişilerden uzaklaşır. NotchPrompter ile metniniz tam kameranın altında durur, böylece baştan sona göz temasını korursunuz.

            Siz konuştukça sesinizi takip eder. Ara verin, metinden sapın; o da siz dönene kadar sadece bekler.
            """,
            weeklyTitle: "Haftalık ekip güncellemesi",
            weeklyText: "Günaydın! Bu hafta üç konu var: yeni karşılama akışı, fiyat testi ve konferans planlarımız.",
            youtubeTitle: "YouTube girişi",
            youtubeText: "Selam, kanala tekrar hoş geldiniz. Bugün sıfırdan küçük bir Mac uygulaması yapıyoruz.",
            shots: s(("Okurken göz temasını koruyun", "Metniniz tam kameranın altında durur."),
                     ("Sesinizi takip eder", "Kendi hızınızda konuşun. Durduğunuzda sizi bekler."),
                     ("Metinlerinizi burada yazın", "Basit bir düzenleyici. Word, Markdown veya metin dosyalarını içe aktarın."),
                     ("Ya da oynatın", "Sabit kaydırma. Duraklatmak için imleci üzerine getirin. Hız için kaplumbağa ve tavşan."),
                     ("İzleyicileriniz göremez", "Ekran paylaşımında ve kayıtlarda gizlidir. Apple’ın konuşma tanıma hizmetine giden konuşma dışında hiçbir şey Mac’inizden çıkmaz.")),
            clock: "Sal 09:41"),
    ]

    /// The word the reading screenshots stop at: a few words into the third paragraph, as in English
    /// (word 40 of 96). Counted the way the prompter counts words, so it works for Chinese and Japanese too.
    var readingWord: Int {
        let ns = demoText as NSString
        var starts: [Int] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { _, range, _, _ in
            starts.append(range.location)
        }
        let paragraphs = demoText.components(separatedBy: "\n\n")
        guard paragraphs.count >= 4 else { return 40 }
        let third = (paragraphs[0] + "\n\n" + paragraphs[1] + "\n\n" as NSString).length
        let fourth = third + (paragraphs[2] + "\n\n" as NSString).length
        let first = starts.firstIndex { $0 >= third } ?? 0
        let inThird = starts.filter { $0 >= third && $0 < fourth }.count
        // English: 34 + round(6 × 43 / 43) = 40.
        return first + Int((6.0 * Double(inThird) / 43.0).rounded())
    }
}
#endif
